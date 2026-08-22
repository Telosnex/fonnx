import 'dart:math' as math;
import 'dart:typed_data';

import '../keyword_spotter_types.dart';
import 'context_graph.dart';

final class KwsHypothesis {
  KwsHypothesis({
    required this.tokens,
    required this.logProbability,
    required this.contextState,
    List<int>? timestamps,
    List<double>? tokenProbabilities,
    this.trailingBlanks = 0,
  }) : timestamps = timestamps ?? <int>[],
       tokenProbabilities = tokenProbabilities ?? <double>[];

  final List<int> tokens;
  final List<int> timestamps;
  final List<double> tokenProbabilities;
  double logProbability;
  ContextState contextState;
  int trailingBlanks;

  String get key => tokens.join('-');

  KwsHypothesis copy() => KwsHypothesis(
    tokens: List<int>.of(tokens),
    timestamps: List<int>.of(timestamps),
    tokenProbabilities: List<double>.of(tokenProbabilities),
    logProbability: logProbability,
    contextState: contextState,
    trailingBlanks: trailingBlanks,
  );
}

final class TransducerKeywordDecoder {
  TransducerKeywordDecoder({
    required KwsOnnxBackend backend,
    required ContextGraph graph,
    this.maxActivePaths = 4,
    this.trailingBlankFrames = 1,
  }) : _backend = backend,
       _graph = graph {
    reset();
  }

  static const blankId = 0;
  static const unknownId = 2;
  static const contextSize = 2;
  static const vocabSize = 500;
  static const joinerDimension = 320;

  final KwsOnnxBackend _backend;
  ContextGraph _graph;
  final int maxActivePaths;
  final int trailingBlankFrames;
  var _frameOffset = 0;
  late Map<String, KwsHypothesis> _hypotheses;

  int get trailingBlanks => _best(_hypotheses.values).trailingBlanks;

  void setGraph(ContextGraph graph) {
    _graph = graph;
    reset();
  }

  void reset() {
    final hypothesis = KwsHypothesis(
      tokens: <int>[-1, blankId],
      logProbability: 0,
      contextState: _graph.root,
    );
    _hypotheses = <String, KwsHypothesis>{hypothesis.key: hypothesis};
    _frameOffset = 0;
  }

  Future<List<KeywordDetection>> decode(KwsEncoderOutput encoder) async {
    if (encoder.values.length != encoder.frameCount * joinerDimension) {
      throw StateError('Invalid encoder output shape');
    }
    final detections = <KeywordDetection>[];

    for (var frame = 0; frame < encoder.frameCount; frame++) {
      final previous = _hypotheses.values.toList(growable: false);
      final contexts = Int64List(previous.length * contextSize);
      for (var i = 0; i < previous.length; i++) {
        final tokens = previous[i].tokens;
        contexts[i * 2] = tokens[tokens.length - 2];
        contexts[i * 2 + 1] = tokens.last;
      }
      final decoderVectors = await _backend.runDecoder(contexts);
      final encoderVectors = Float32List(previous.length * joinerDimension);
      final frameStart = frame * joinerDimension;
      final frameVector = encoder.values.sublist(
        frameStart,
        frameStart + joinerDimension,
      );
      for (var i = 0; i < previous.length; i++) {
        encoderVectors.setRange(
          i * joinerDimension,
          (i + 1) * joinerDimension,
          frameVector,
        );
      }
      final logits = await _backend.runJoiner(encoderVectors, decoderVectors);
      if (logits.length != previous.length * vocabSize) {
        throw StateError('Invalid joiner output shape');
      }
      _logSoftmaxRows(logits, vocabSize);

      final candidates = <_Candidate>[];
      for (
        var hypothesisIndex = 0;
        hypothesisIndex < previous.length;
        hypothesisIndex++
      ) {
        final base = hypothesisIndex * vocabSize;
        for (var token = 0; token < vocabSize; token++) {
          candidates.add(
            _Candidate(
              hypothesisIndex,
              token,
              logits[base + token] + previous[hypothesisIndex].logProbability,
              logits[base + token],
            ),
          );
        }
      }
      candidates.sort((left, right) => right.combined.compareTo(left.combined));

      final next = <String, KwsHypothesis>{};
      final count = math.min(maxActivePaths, candidates.length);
      for (var i = 0; i < count; i++) {
        final candidate = candidates[i];
        final hypothesis = previous[candidate.hypothesisIndex].copy();
        var contextScore = 0.0;
        if (candidate.token != blankId && candidate.token != unknownId) {
          hypothesis.tokens.add(candidate.token);
          hypothesis.timestamps.add(frame + _frameOffset);
          hypothesis.tokenProbabilities.add(math.exp(candidate.acoustic));
          hypothesis.trailingBlanks = 0;
          final step = _graph.forward(hypothesis.contextState, candidate.token);
          contextScore = step.score;
          hypothesis.contextState = step.state;
          if (hypothesis.contextState.token == -1) {
            hypothesis.tokens
              ..clear()
              ..addAll(const [-1, blankId]);
            hypothesis.timestamps.clear();
            hypothesis.tokenProbabilities.clear();
          }
        } else {
          hypothesis.trailingBlanks++;
        }
        hypothesis.logProbability = candidate.combined + contextScore;
        _addOrMerge(next, hypothesis);
      }

      final best = _best(next.values);
      final matched = _graph.matched(best.contextState);
      if (matched != null &&
          best.trailingBlanks > trailingBlankFrames &&
          best.tokenProbabilities.length >= matched.level) {
        final probabilities = best.tokenProbabilities.sublist(
          best.tokenProbabilities.length - matched.level,
        );
        final mean = probabilities.reduce((a, b) => a + b) / matched.level;
        if (mean >= matched.acousticThreshold) {
          final timestamps = best.timestamps.sublist(
            best.timestamps.length - matched.level,
          );
          detections.add(
            KeywordDetection(
              phrase: matched.phrase,
              detectedAt: Duration(milliseconds: timestamps.last * 40),
              tokenTimestamps: timestamps
                  .map((frame) => Duration(milliseconds: frame * 40))
                  .toList(growable: false),
              meanTokenProbability: mean,
            ),
          );
          final empty = KwsHypothesis(
            tokens: <int>[-1, blankId],
            logProbability: 0,
            contextState: _graph.root,
          );
          next
            ..clear()
            ..[empty.key] = empty;
        }
      }
      _hypotheses = next;
    }
    _frameOffset += encoder.frameCount;
    return detections;
  }

  static void _addOrMerge(
    Map<String, KwsHypothesis> hypotheses,
    KwsHypothesis hypothesis,
  ) {
    final existing = hypotheses[hypothesis.key];
    if (existing == null) {
      hypotheses[hypothesis.key] = hypothesis;
    } else {
      existing.logProbability = _logAdd(
        existing.logProbability,
        hypothesis.logProbability,
      );
    }
  }

  static KwsHypothesis _best(Iterable<KwsHypothesis> hypotheses) =>
      hypotheses.reduce(
        (left, right) =>
            left.logProbability >= right.logProbability ? left : right,
      );
}

final class _Candidate {
  const _Candidate(
    this.hypothesisIndex,
    this.token,
    this.combined,
    this.acoustic,
  );

  final int hypothesisIndex;
  final int token;
  final double combined;
  final double acoustic;
}

void _logSoftmaxRows(Float32List values, int columns) {
  for (var rowStart = 0; rowStart < values.length; rowStart += columns) {
    var maximum = double.negativeInfinity;
    for (var i = rowStart; i < rowStart + columns; i++) {
      maximum = math.max(maximum, values[i]);
    }
    var sum = 0.0;
    for (var i = rowStart; i < rowStart + columns; i++) {
      sum += math.exp(values[i] - maximum);
    }
    final normalizer = maximum + math.log(sum);
    for (var i = rowStart; i < rowStart + columns; i++) {
      values[i] -= normalizer;
    }
  }
}

double _logAdd(double left, double right) {
  if (left == double.negativeInfinity) return right;
  if (right == double.negativeInfinity) return left;
  final maximum = math.max(left, right);
  return maximum +
      math.log(math.exp(left - maximum) + math.exp(right - maximum));
}
