import 'dart:async';

import 'futo_swipe.dart';
import 'src/futo_swipe_isolate.dart';

Future<FutoSwipe> getFutoSwipe({
  required FutoSwipeBundle bundle,
  required List<FutoSwipeWord> lexicon,
  required bool includeModelVocabulary,
  required int beamWidth,
}) async {
  final manager = FutoSwipeIsolateManager();
  final lexiconSize = await manager.start(
    bundle: bundle,
    lexicon: lexicon,
    includeModelVocabulary: includeModelVocabulary,
    beamWidth: beamWidth,
  );
  return FutoSwipeNative._(manager).._lexiconSize = lexiconSize;
}

/// Native Assets supply ONNX Runtime on Android, iOS, Linux, macOS, and
/// Windows. Sessions, embedding tables, and the lexicon live in one worker
/// isolate, so search never blocks the UI isolate.
final class FutoSwipeNative extends FutoSwipe {
  FutoSwipeNative._(this._manager);

  final FutoSwipeIsolateManager _manager;
  var _lexiconSize = 0;
  var _closed = false;
  Future<void> _pending = Future<void>.value();

  @override
  int get lexiconSize => _lexiconSize;

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
    return _enqueue(() => _manager.decode(points, keys, words, count));
  }

  @override
  Future<FutoSwipeEmissions> emissions(
    Iterable<FutoSwipePoint> trace, {
    FutoSwipeLayout? layout,
  }) {
    _ensureOpen();
    final points = validatedFutoTrace(trace);
    final keys = layout ?? FutoSwipeLayout.englishQwerty();
    return _enqueue(() => _manager.emissions(points, keys));
  }

  @override
  Future<List<double>> scoreWords(
    Iterable<String> previousWords,
    Iterable<String> words,
  ) {
    _ensureOpen();
    final context = validatedFutoWords(previousWords, 'previousWords');
    final candidates = validatedFutoWords(words, 'words');
    return _enqueue(() => _manager.scoreWords(context, candidates));
  }

  @override
  Future<List<FutoWordScore>> predictNextWords(
    Iterable<String> previousWords, {
    int count = 5,
  }) {
    _ensureOpen();
    final context = validatedFutoWords(previousWords, 'previousWords');
    final limit = validatedFutoCount(count, 'count');
    return _enqueue(() => _manager.predictNextWords(context, limit));
  }

  @override
  Future<int> setLexicon(
    Iterable<FutoSwipeWord> lexicon, {
    bool includeModelVocabulary = true,
  }) {
    _ensureOpen();
    final words = validatedFutoLexicon(lexicon);
    return _enqueue(() async {
      return _lexiconSize = await _manager.setLexicon(
        words,
        includeModelVocabulary,
      );
    });
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _enqueue(_manager.close);
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
