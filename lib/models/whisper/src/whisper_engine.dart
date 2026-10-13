import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'whisper_features.dart';
import 'whisper_vocabulary.dart';

/// Runs the two ONNX graphs of a Whisper model. A backend keeps the encoder
/// output and the decoder's key/value cache between calls.
abstract interface class WhisperOnnxBackend {
  /// Runs the encoder on [features], 80 × 3000 log-mel values, and starts a
  /// new decoder cache with [batch] rows.
  Future<void> encode(Float32List features, int batch);

  /// Runs one decoder step and returns the logits of the last position of
  /// each row: rows × vocabulary.
  ///
  /// [tokens] holds the rows, each [length] tokens long. On the first step
  /// after [encode], each row is the prompt and [parents] is null. On a later
  /// step, each row is one token, and row i continues cache row [parents]\[i].
  Future<Float32List> decode(Int32List tokens, int length, Int32List? parents);

  Future<void> close();
}

/// The vocabulary of the multilingual Whisper models, before Whisper large-v3.
const whisperVocabularySize = 51865;

/// Transcribes English audio with beam search.
///
/// The search matches Hugging Face's `generate` with `num_beams` beams and a
/// length penalty of 1, and Whisper's token suppression. fonnx used 2 beams
/// before this, in the ORT BeamSearch graph. Greedy decoding (1 beam) can
/// miss the first sentence when speech starts at 0 s.
final class WhisperEngine {
  WhisperEngine(this._backend, {this.beams = 2, this.maxNewTokens = 220})
    : assert(beams >= 1),
      assert(maxNewTokens >= 1 && maxNewTokens <= 444);

  final WhisperOnnxBackend _backend;
  final int beams;

  /// The decoder has 448 positions. The prompt uses 4.
  final int maxNewTokens;

  static const prompt = <int>[
    whisperStartOfTranscript,
    whisperEnglish,
    whisperTranscribe,
    whisperNoTimestamps,
  ];

  Future<void> close() => _backend.close();

  Future<String> transcribe(Float32List samples) async =>
      decodeWhisperText(await transcribeTokens(samples));

  /// Returns the text tokens of the best hypothesis.
  Future<List<int>> transcribeTokens(Float32List samples) async {
    final features = whisperLogMel(samples);
    await _backend.encode(features, beams);

    var logits = await _backend.decode(
      Int32List.fromList([for (var b = 0; b < beams; b++) ...prompt]),
      prompt.length,
      null,
    );
    // On the first step every row holds the same prompt, so only row 0
    // gives candidates.
    var running = <_Hypothesis>[const _Hypothesis(<int>[], 0)];
    final finished = _Finished(beams);
    for (var step = 0; ; step++) {
      final candidates = <_Candidate>[];
      for (var row = 0; row < running.length; row++) {
        _topCandidates(
          logits,
          row,
          running[row].score,
          2 * beams,
          first: step == 0,
          into: candidates,
        );
      }
      candidates.sort((a, b) => b.score.compareTo(a.score));

      final next = <_Hypothesis>[];
      final parents = Int32List(beams);
      for (var rank = 0; rank < candidates.length; rank++) {
        final candidate = candidates[rank];
        final parent = running[candidate.row];
        if (candidate.token == whisperEndOfText) {
          // Like Hugging Face: an end only counts if it ranks in the top
          // [beams] candidates.
          if (rank < beams) finished.add(parent.tokens, candidate.score);
          continue;
        }
        parents[next.length] = candidate.row;
        next.add(
          _Hypothesis([...parent.tokens, candidate.token], candidate.score),
        );
        if (next.length == beams) break;
      }
      running = next;

      final generated = step + 1;
      if (generated >= maxNewTokens ||
          finished.isDone(running.first.score, generated)) {
        break;
      }
      logits = await _backend.decode(
        Int32List.fromList([for (final h in running) h.tokens.last]),
        1,
        parents,
      );
    }
    for (final hypothesis in running) {
      finished.add(hypothesis.tokens, hypothesis.score);
    }
    return finished.best;
  }

  /// Adds the [count] best tokens of logits [row] to [into], scored as
  /// [base] plus the token's log probability.
  static void _topCandidates(
    Float32List logits,
    int row,
    double base,
    int count, {
    required bool first,
    required List<_Candidate> into,
  }) {
    final vocabulary = whisperVocabularySize;
    final offset = row * vocabulary;
    if (logits.length < offset + vocabulary) {
      throw StateError('Whisper logits are too short: ${logits.length}');
    }
    // Log-softmax over the whole vocabulary, then suppression, like Hugging
    // Face's logits processors.
    var maximum = double.negativeInfinity;
    for (var i = 0; i < vocabulary; i++) {
      final value = logits[offset + i];
      if (value > maximum) maximum = value;
    }
    var sum = 0.0;
    for (var i = 0; i < vocabulary; i++) {
      sum += math.exp(logits[offset + i] - maximum);
    }
    final logSum = maximum + math.log(sum);

    final suppressed = first ? _suppressedFirst : _suppressed;
    final bestTokens = Int32List(count)..fillRange(0, count, -1);
    final bestValues = Float64List(count)
      ..fillRange(0, count, double.negativeInfinity);
    var threshold = double.negativeInfinity;
    for (var i = 0; i < vocabulary; i++) {
      final value = logits[offset + i];
      if (value <= threshold || suppressed[i] != 0) continue;
      var j = count - 1;
      while (j > 0 && bestValues[j - 1] < value) {
        bestValues[j] = bestValues[j - 1];
        bestTokens[j] = bestTokens[j - 1];
        j--;
      }
      bestValues[j] = value;
      bestTokens[j] = i;
      threshold = bestValues[count - 1];
    }
    for (var j = 0; j < count; j++) {
      if (bestTokens[j] < 0) break;
      into.add(_Candidate(row, bestTokens[j], base + bestValues[j] - logSum));
    }
  }

  // 1 for each token that is never generated: Whisper's suppress list, and
  // every special token except the end of text.
  static final Uint8List _suppressed = () {
    final flags = Uint8List(whisperVocabularySize);
    for (final token in whisperSuppressTokens) {
      flags[token] = 1;
    }
    for (var i = whisperStartOfTranscript; i < whisperVocabularySize; i++) {
      flags[i] = 1;
    }
    return flags;
  }();

  static final Uint8List _suppressedFirst = () {
    final flags = Uint8List.fromList(_suppressed);
    for (final token in whisperBeginSuppressTokens) {
      flags[token] = 1;
    }
    return flags;
  }();
}

/// Decodes Whisper text tokens to a string. Special tokens are skipped.
String decodeWhisperText(Iterable<int> tokens) {
  final bytes = <int>[];
  for (final token in tokens) {
    if (token < 0 || token >= whisperTextPieces.length) continue;
    for (final unit in whisperTextPieces[token].codeUnits) {
      bytes.add(_byteForUnit[unit]);
    }
  }
  return utf8.decode(bytes, allowMalformed: true).trim();
}

/// GPT-2 byte-level BPE stores each byte as a printable character. This is
/// the inverse of that map.
final Uint8List _byteForUnit = () {
  final printable = <int>[
    for (var b = 0x21; b <= 0x7E; b++) b,
    for (var b = 0xA1; b <= 0xAC; b++) b,
    for (var b = 0xAE; b <= 0xFF; b++) b,
  ];
  final table = Uint8List(512);
  final printableSet = printable.toSet();
  for (final b in printable) {
    table[b] = b;
  }
  var next = 256;
  for (var b = 0; b < 256; b++) {
    if (!printableSet.contains(b)) table[next++] = b;
  }
  return table;
}();

final class _Hypothesis {
  const _Hypothesis(this.tokens, this.score);

  final List<int> tokens;

  /// Sum of the token log probabilities.
  final double score;
}

final class _Candidate {
  const _Candidate(this.row, this.token, this.score);

  final int row;
  final int token;
  final double score;
}

/// The best finished hypotheses, scored by mean log probability per token
/// (a length penalty of 1).
final class _Finished {
  _Finished(this._capacity);

  final int _capacity;
  final _items = <(List<int>, double)>[];

  void add(List<int> tokens, double score) {
    _items
      ..add((tokens, score / math.max(tokens.length, 1)))
      ..sort((a, b) => b.$2.compareTo(a.$2));
    if (_items.length > _capacity) _items.removeLast();
  }

  /// Whether no running hypothesis can beat the finished ones. This is
  /// Hugging Face's check for `early_stopping=False`.
  bool isDone(double bestRunningScore, int length) =>
      _items.length >= _capacity && _items.last.$2 >= bestRunningScore / length;

  List<int> get best => _items.first.$1;
}
