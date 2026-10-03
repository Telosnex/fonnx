import 'dart:math' as math;
import 'dart:typed_data';

import '../futo_swipe_types.dart';
import 'context_hash.dart';
import 'ctc_prefix_search.dart';
import 'trace_resampler.dart';

const _decoderScoringKey = 'encoder:honorable_sturgeon decoder:magic_macaw';
const _contextScoringKey =
    'encoder:honorable_sturgeon decoder:magic_macaw '
    'contextlm:hungry_jellyfish';

/// Scoring weights from the bundle's `scoring.json`.
final class FutoScoringWeights {
  const FutoScoringWeights({
    required this.gamma,
    required this.beta,
    required this.lambda,
    required this.alpha,
    required this.gammaPrune,
    required this.betaPrune,
  });

  factory FutoScoringWeights.fromJson(Map<String, dynamic> json, String key) {
    final entry = json[key];
    if (entry is! Map) {
      throw FormatException('FUTO scoring configuration lacks "$key"');
    }
    double read(String name) {
      final value = entry[name];
      if (value is! num || !value.isFinite) {
        throw FormatException('FUTO scoring "$key" has invalid "$name"');
      }
      return value.toDouble();
    }

    return FutoScoringWeights(
      gamma: read('gamma'),
      beta: read('beta'),
      lambda: read('lambda'),
      alpha: read('alpha'),
      gammaPrune: read('gamma_prune'),
      betaPrune: read('beta_prune'),
    );
  }

  final double gamma;
  final double beta;
  final double lambda;
  final double alpha;
  final double gammaPrune;
  final double betaPrune;
}

/// Platform-independent FUTO Swipe inference and decoding.
///
/// Native code runs this engine in a worker isolate. The Web runs it on the
/// page thread and runs ONNX graphs in a Web Worker.
final class FutoSwipeEngine {
  FutoSwipeEngine._({
    required FutoSwipeOnnxBackend backend,
    required List<String> vocabulary,
    required this.decoderWeights,
    required this.contextWeights,
    required FutoContextEmbeddings embeddings,
    required int beamWidth,
  }) : _backend = backend,
       _vocabulary = vocabulary,
       _embeddings = embeddings,
       _beamWidth = beamWidth {
    // ID 0 is padding. The vocabulary has one more word than exact rows, so
    // its final word uses the hashed path.
    for (var id = 1; id < futoContextVocabularySize; id++) {
      final word = vocabulary[id - 1];
      _exactIds[word] = id;
      _lowercaseIds.putIfAbsent(word.toLowerCase(), () => id);
    }
  }

  static Future<FutoSwipeEngine> create({
    required FutoSwipeOnnxBackend backend,
    required List<String> vocabulary,
    required Map<String, dynamic> scoring,
    required List<FutoSwipeWord> lexicon,
    required bool includeModelVocabulary,
    required int beamWidth,
  }) async {
    if (vocabulary.length != futoContextVocabularySize) {
      throw FormatException(
        'FUTO vocabulary has ${vocabulary.length} words; '
        'expected $futoContextVocabularySize',
      );
    }
    final engine = FutoSwipeEngine._(
      backend: backend,
      vocabulary: List<String>.unmodifiable(vocabulary),
      decoderWeights: FutoScoringWeights.fromJson(scoring, _decoderScoringKey),
      contextWeights: FutoScoringWeights.fromJson(scoring, _contextScoringKey),
      embeddings: await backend.loadEmbeddings(),
      beamWidth: beamWidth,
    );
    engine.setLexicon(lexicon, includeModelVocabulary: includeModelVocabulary);
    return engine;
  }

  final FutoSwipeOnnxBackend _backend;
  final List<String> _vocabulary;
  final FutoContextEmbeddings _embeddings;
  final int _beamWidth;
  final FutoScoringWeights decoderWeights;
  final FutoScoringWeights contextWeights;
  final _exactIds = <String, int>{};
  final _lowercaseIds = <String, int>{};
  final _bucketCache = <String, List<int>>{};
  LexiconNode _root = LexiconNode('', -1);
  var _lexiconSize = 0;
  FutoSwipeLayout? _layout;
  Float32List? _layoutKeys;
  Uint8List? _layoutMask;
  String? _contextKey;
  Float32List? _contextState;
  var _closed = false;

  /// Swipeable lexicon spellings, after search-key filtering.
  int get lexiconSize => _lexiconSize;

  /// Replaces all swipe words. Model vocabulary words are added first.
  void setLexicon(
    List<FutoSwipeWord> lexicon, {
    required bool includeModelVocabulary,
  }) {
    _ensureOpen();
    final root = LexiconNode('', -1);
    var size = 0;
    if (includeModelVocabulary) {
      for (final word in _vocabulary) {
        if (addLexiconWord(root, word, 0)) size++;
      }
    }
    for (final word in lexicon) {
      if (addLexiconWord(root, word.text, word.frequency)) size++;
    }
    _root = root;
    _lexiconSize = size;
  }

  /// Runs the encoder and paired English decoder.
  Future<FutoSwipeEmissions> emissions(
    List<FutoSwipePoint> trace,
    FutoSwipeLayout layout,
  ) async {
    _ensureOpen();
    if (!identical(layout, _layout)) {
      _layoutKeys = layout.toKeyTensor();
      _layoutMask = layout.toMaskTensor();
      _layout = layout;
    }
    final encoded = await _backend.runEncoder(
      resampleFutoTrace(trace),
      _layoutKeys!,
      _layoutMask!,
    );
    // Decoder input per step: 26 letter scores, blank, 64 coefficients, and
    // intention. Unused key slots 26-63 are not part of it.
    final combined = Float32List(futoSwipeTimeSteps * 92);
    for (var t = 0; t < futoSwipeTimeSteps; t++) {
      final row = t * 92;
      combined.setRange(row, row + 26, encoded.logEmissions, t * 65);
      combined[row + 26] = encoded.logEmissions[t * 65 + 64];
      combined.setRange(row + 27, row + 91, encoded.coefficients, t * 64);
      combined[row + 91] = encoded.intention[t];
    }
    final refined = await _backend.runDecoder(combined);
    for (final value in refined) {
      if (!value.isFinite) {
        throw StateError('FUTO decoder produced a non-finite score');
      }
    }
    return FutoSwipeEmissions(refined);
  }

  /// Ranks lexicon words for [trace].
  ///
  /// When [previousWords] is null, ranking uses the encoder+decoder weights.
  /// Otherwise it adds ContextLM scores; an empty list means start of text.
  Future<List<FutoSwipeCandidate>> decode(
    List<FutoSwipePoint> trace,
    FutoSwipeLayout layout, {
    List<String>? previousWords,
    required int maxCandidates,
  }) async {
    final refined = await emissions(trace, layout);
    // Both bundle configurations use the same pruning weights, so the beam
    // does not depend on whether context is enabled.
    final weights = previousWords == null ? decoderWeights : contextWeights;
    final states = ctcPrefixSearch(
      refined.logScores,
      futoSwipeTimeSteps,
      futoSwipeClassCount,
      _root,
      beam: _beamWidth,
      gamma: weights.gammaPrune,
      beta: weights.betaPrune,
    );
    final state = previousWords == null
        ? null
        : await _contextStateFor(previousWords);
    final ranked = <FutoSwipeCandidate>[];
    for (final entry in states.entries) {
      final node = entry.key;
      if (!node.isWord) continue;
      final length = node.text.length;
      final base =
          entry.value.total / math.pow(length, weights.gamma) +
          weights.beta * length;
      final surfaces = <(String, double)>[
        for (final surface in node.surfaces)
          (
            surface.text,
            base +
                weights.lambda * surface.frequency +
                (state == null
                    ? 0
                    : weights.alpha * _scoreWord(state, surface.text)),
          ),
      ]..sort((a, b) => b.$2.compareTo(a.$2));
      ranked.add(
        FutoSwipeCandidate(
          word: surfaces.first.$1,
          searchKey: node.text,
          alternatives: surfaces.skip(1).map((s) => s.$1),
          score: surfaces.first.$2,
        ),
      );
    }
    ranked.sort((a, b) => b.score.compareTo(a.score));
    return ranked.take(maxCandidates).toList(growable: false);
  }

  /// ContextLM scores for [words] after [previousWords].
  Future<List<double>> scoreWords(
    List<String> previousWords,
    List<String> words,
  ) async {
    final state = await _contextStateFor(previousWords);
    return List<double>.unmodifiable(
      words.map((word) => _scoreWord(state, word)),
    );
  }

  /// Highest-scoring exact-vocabulary words after [previousWords].
  Future<List<FutoWordScore>> predictNextWords(
    List<String> previousWords,
    int count,
  ) async {
    final state = await _contextStateFor(previousWords);
    final embeddings = _embeddings.exactEmbeddings;
    final biases = _embeddings.exactBiases;
    final best = <FutoWordScore>[];
    for (var id = 1; id < futoContextVocabularySize; id++) {
      var score = biases[id].toDouble();
      final row = id * futoContextDimension;
      for (var d = 0; d < futoContextDimension; d++) {
        score += state[d] * embeddings[row + d];
      }
      if (best.length == count && score <= best.last.score) continue;
      var index = best.length;
      while (index > 0 && best[index - 1].score < score) {
        index--;
      }
      best.insert(index, FutoWordScore(_vocabulary[id - 1], score));
      if (best.length > count) best.removeLast();
    }
    return List<FutoWordScore>.unmodifiable(best);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _backend.close();
  }

  /// Final-position ContextLM state, cached until the context changes.
  Future<Float32List> _contextStateFor(List<String> previousWords) async {
    _ensureOpen();
    final tokens = previousWords.length > futoContextLength
        ? previousWords.sublist(previousWords.length - futoContextLength)
        : previousWords;
    final key = tokens.join('\u0000');
    final cached = _contextState;
    if (cached != null && key == _contextKey) return cached;
    final ids = Int32List(futoContextLength);
    final buckets = Int32List(futoContextLength * 2);
    for (var i = 0; i < tokens.length; i++) {
      final id = _contextId(tokens[i]);
      ids[i] = id ?? futoContextHashedTokenId;
      if (id == null) {
        final hashed = _buckets(tokens[i]);
        buckets[i * 2] = hashed[0];
        buckets[i * 2 + 1] = hashed[1];
      }
    }
    final states = await _backend.runContext(ids, buckets);
    if (states.length != futoContextLength * futoContextDimension) {
      throw StateError('Unexpected ContextLM output length ${states.length}');
    }
    // Inputs are right-padded. Read the state at the final real position.
    final offset = math.max(0, tokens.length - 1) * futoContextDimension;
    final state = Float32List.sublistView(
      Float32List.fromList(states),
      offset,
      offset + futoContextDimension,
    );
    _contextKey = key;
    _contextState = state;
    return state;
  }

  double _scoreWord(Float32List state, String word) {
    final id = _contextId(word);
    final rows = id == null ? _buckets(word) : [id];
    final embeddings = id == null
        ? _embeddings.hashedEmbeddings
        : _embeddings.exactEmbeddings;
    final biases = id == null
        ? _embeddings.hashedBiases
        : _embeddings.exactBiases;
    var score = 0.0;
    for (final row in rows) {
      score += biases[row];
      for (var d = 0; d < futoContextDimension; d++) {
        score += state[d] * embeddings[row * futoContextDimension + d];
      }
    }
    return score;
  }

  int? _contextId(String word) =>
      _exactIds[word] ?? _lowercaseIds[word.toLowerCase()];

  List<int> _buckets(String word) {
    final cached = _bucketCache[word];
    if (cached != null) return cached;
    // Hashing uses BigInt. Bound the cache for long-lived keyboard sessions.
    if (_bucketCache.length >= _bucketCacheLimit) _bucketCache.clear();
    return _bucketCache[word] = futoContextBuckets(word);
  }

  static const _bucketCacheLimit = 50000;

  void _ensureOpen() {
    if (_closed) throw StateError('FUTO Swipe is closed');
  }
}
