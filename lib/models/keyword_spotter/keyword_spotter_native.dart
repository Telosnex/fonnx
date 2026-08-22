import 'dart:async';
import 'dart:typed_data';

import 'keyword_spotter.dart';
import 'src/keyword_spotter_isolate.dart';

Future<KeywordSpotter> getKeywordSpotter({
  required KeywordSpotterBundle bundle,
  required List<KeywordPhrase> keywords,
  required int maxActivePaths,
  required int trailingBlankFrames,
}) async {
  final spotter = KeywordSpotterNative._();
  await spotter._manager.start(
    bundle: bundle,
    keywords: keywords,
    maxActivePaths: maxActivePaths,
    trailingBlankFrames: trailingBlankFrames,
  );
  return spotter;
}

/// Native Assets makes the same Dart FFI implementation available on Android,
/// iOS, Linux, macOS, and Windows. ONNX state and decoding live in a long-lived
/// worker isolate so audio ingestion never blocks the UI isolate.
final class KeywordSpotterNative extends KeywordSpotter {
  KeywordSpotterNative._();

  final KeywordSpotterIsolateManager _manager = KeywordSpotterIsolateManager();
  final StreamController<KeywordDetection> _detections =
      StreamController<KeywordDetection>.broadcast(sync: true);
  var _closed = false;
  Future<void> _pending = Future<void>.value();

  @override
  Stream<KeywordDetection> get detections => _detections.stream;

  @override
  Future<void> acceptSamples(Float32List samples, {int sampleRate = 16000}) {
    _ensureOpen();
    if (sampleRate != 16000) {
      throw ArgumentError.value(
        sampleRate,
        'sampleRate',
        'English keyword spotting currently requires 16 kHz mono audio',
      );
    }
    return _enqueue(() async {
      for (final detection in await _manager.accept(samples)) {
        _detections.add(detection);
      }
    });
  }

  @override
  Future<void> finish() {
    _ensureOpen();
    return _enqueue(() async {
      for (final detection in await _manager.finish()) {
        _detections.add(detection);
      }
    });
  }

  @override
  Future<String> transcribeSamples(
    Float32List samples, {
    int sampleRate = 16000,
  }) {
    _ensureOpen();
    if (sampleRate != 16000) {
      throw ArgumentError.value(
        sampleRate,
        'sampleRate',
        'English keyword spotting currently requires 16 kHz mono audio',
      );
    }
    return _enqueue(() => _manager.transcribe(samples));
  }

  @override
  Future<void> setKeywords(List<KeywordPhrase> keywords) {
    _ensureOpen();
    return _enqueue(() => _manager.setKeywords(keywords));
  }

  @override
  Future<void> reset() {
    _ensureOpen();
    return _enqueue(_manager.reset);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _enqueue(_manager.close);
    await _detections.close();
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final result = _pending.then((_) => operation());
    _pending = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }

  void _ensureOpen() {
    if (_closed) throw StateError('Keyword spotter is closed');
  }
}
