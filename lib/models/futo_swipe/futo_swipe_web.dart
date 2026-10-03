import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'futo_swipe.dart';
import 'src/futo_swipe_engine.dart';

extension type _LoadResult._(JSObject _) implements JSObject {
  external JSString get vocabulary;
  external JSString get scoring;
  external JSFloat32Array get exactEmbeddings;
  external JSFloat32Array get exactBiases;
  external JSFloat32Array get hashedEmbeddings;
  external JSFloat32Array get hashedBiases;
}

extension type _EncoderResult._(JSObject _) implements JSObject {
  external JSFloat32Array get logEmissions;
  external JSFloat32Array get coefficients;
  external JSFloat32Array get intention;
}

@JS('window.fonnxFutoSwipeLoad')
external JSPromise<_LoadResult> _loadJs(
  JSString engineId,
  JSString encoderPath,
  JSString decoderPath,
  JSString contextModelPath,
  JSString embeddingsPath,
  JSString vocabularyPath,
  JSString scoringPath,
);

@JS('window.fonnxFutoSwipeEncoder')
external JSPromise<_EncoderResult> _encoderJs(
  JSString engineId,
  JSFloat32Array features,
  JSFloat32Array layoutKeys,
  JSUint8Array layoutMask,
);

@JS('window.fonnxFutoSwipeDecoder')
external JSPromise<JSFloat32Array> _decoderJs(
  JSString engineId,
  JSFloat32Array features,
);

@JS('window.fonnxFutoSwipeContext')
external JSPromise<JSFloat32Array> _contextJs(
  JSString engineId,
  JSInt32Array tokenIds,
  JSInt32Array hashBuckets,
);

@JS('window.fonnxFutoSwipeClose')
external JSPromise<JSAny?> _closeJs(JSString engineId);

Future<FutoSwipe> getFutoSwipe({
  required FutoSwipeBundle bundle,
  required List<FutoSwipeWord> lexicon,
  required bool includeModelVocabulary,
  required int beamWidth,
}) async {
  final backend = WebFutoSwipeOnnxBackend();
  final (:vocabulary, :scoring) = await backend.load(bundle);
  try {
    final engine = await FutoSwipeEngine.create(
      backend: backend,
      vocabulary: const LineSplitter().convert(vocabulary),
      scoring: jsonDecode(scoring) as Map<String, dynamic>,
      lexicon: lexicon,
      includeModelVocabulary: includeModelVocabulary,
      beamWidth: beamWidth,
    );
    return FutoSwipeWeb._(engine);
  } catch (_) {
    await backend.close();
    rethrow;
  }
}

/// ONNX Runtime Web runs in a Worker. Lexicon search runs on the page thread.
final class FutoSwipeWeb extends FutoSwipe {
  FutoSwipeWeb._(this._engine);

  final FutoSwipeEngine _engine;
  var _closed = false;
  Future<void> _pending = Future<void>.value();

  @override
  int get lexiconSize => _engine.lexiconSize;

  @override
  Future<List<FutoSwipeCandidate>> decode(
    Iterable<FutoSwipePoint> trace, {
    FutoSwipeLayout? layout,
    Iterable<String>? previousWords,
    int maxCandidates = 3,
  }) {
    _ensureOpen();
    final points = validatedFutoTrace(trace);
    final words = previousWords == null
        ? null
        : validatedFutoWords(previousWords, 'previousWords');
    final count = validatedFutoCount(maxCandidates, 'maxCandidates');
    final keys = layout ?? FutoSwipeLayout.englishQwerty();
    return _enqueue(
      () => _engine.decode(
        points,
        keys,
        previousWords: words,
        maxCandidates: count,
      ),
    );
  }

  @override
  Future<FutoSwipeEmissions> emissions(
    Iterable<FutoSwipePoint> trace, {
    FutoSwipeLayout? layout,
  }) {
    _ensureOpen();
    final points = validatedFutoTrace(trace);
    final keys = layout ?? FutoSwipeLayout.englishQwerty();
    return _enqueue(() => _engine.emissions(points, keys));
  }

  @override
  Future<List<double>> scoreWords(
    Iterable<String> previousWords,
    Iterable<String> words,
  ) {
    _ensureOpen();
    final context = validatedFutoWords(previousWords, 'previousWords');
    final candidates = validatedFutoWords(words, 'words');
    return _enqueue(() => _engine.scoreWords(context, candidates));
  }

  @override
  Future<List<FutoWordScore>> predictNextWords(
    Iterable<String> previousWords, {
    int count = 5,
  }) {
    _ensureOpen();
    final context = validatedFutoWords(previousWords, 'previousWords');
    final limit = validatedFutoCount(count, 'count');
    return _enqueue(() => _engine.predictNextWords(context, limit));
  }

  @override
  Future<int> setLexicon(
    Iterable<FutoSwipeWord> lexicon, {
    bool includeModelVocabulary = true,
  }) {
    _ensureOpen();
    final words = validatedFutoLexicon(lexicon);
    return _enqueue(() async {
      _engine.setLexicon(words, includeModelVocabulary: includeModelVocabulary);
      return _engine.lexiconSize;
    });
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _enqueue(_engine.close);
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final result = _pending.then((_) => operation());
    _pending = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }

  void _ensureOpen() {
    if (_closed) throw StateError('FUTO Swipe is closed');
  }
}

final class WebFutoSwipeOnnxBackend implements FutoSwipeOnnxBackend {
  WebFutoSwipeOnnxBackend()
    : _engineId =
          'fonnx-futo-${DateTime.now().microsecondsSinceEpoch}-${_nextId++}';

  static var _nextId = 0;
  final String _engineId;
  FutoContextEmbeddings? _embeddings;

  /// Loads the graphs and returns the bundle's text resources.
  Future<({String vocabulary, String scoring})> load(
    FutoSwipeBundle bundle,
  ) async {
    final result = await _loadJs(
      _engineId.toJS,
      bundle.encoderPath.toJS,
      bundle.decoderPath.toJS,
      bundle.contextModelPath.toJS,
      bundle.embeddingsPath.toJS,
      bundle.vocabularyPath.toJS,
      bundle.scoringPath.toJS,
    ).toDart;
    _embeddings = FutoContextEmbeddings(
      exactEmbeddings: result.exactEmbeddings.toDart,
      exactBiases: result.exactBiases.toDart,
      hashedEmbeddings: result.hashedEmbeddings.toDart,
      hashedBiases: result.hashedBiases.toDart,
    );
    return (
      vocabulary: result.vocabulary.toDart,
      scoring: result.scoring.toDart,
    );
  }

  @override
  Future<FutoEncoderOutput> runEncoder(
    Float32List features,
    Float32List layoutKeys,
    Uint8List layoutMask,
  ) async {
    final result = await _encoderJs(
      _engineId.toJS,
      features.toJS,
      layoutKeys.toJS,
      layoutMask.toJS,
    ).toDart;
    return FutoEncoderOutput(
      logEmissions: result.logEmissions.toDart,
      coefficients: result.coefficients.toDart,
      intention: result.intention.toDart,
    );
  }

  @override
  Future<Float32List> runDecoder(Float32List features) async =>
      (await _decoderJs(_engineId.toJS, features.toJS).toDart).toDart;

  @override
  Future<Float32List> runContext(
    Int32List tokenIds,
    Int32List hashBuckets,
  ) async => (await _contextJs(
    _engineId.toJS,
    tokenIds.toJS,
    hashBuckets.toJS,
  ).toDart).toDart;

  @override
  Future<FutoContextEmbeddings> loadEmbeddings() async {
    final embeddings = _embeddings;
    if (embeddings == null) {
      throw StateError('FUTO Swipe Web backend is not loaded');
    }
    return embeddings;
  }

  @override
  Future<void> close() async {
    await _closeJs(_engineId.toJS).toDart;
  }
}
