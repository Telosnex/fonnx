import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'keyword_spotter.dart';
import 'src/keyword_spotter_engine.dart';

@JS('window.fonnxKwsLoad')
external JSPromise<JSAny?> _loadJs(
  JSString engineId,
  JSString encoderPath,
  JSString decoderPath,
  JSString joinerPath,
);

@JS('window.fonnxKwsEncoder')
external JSPromise<JSFloat32Array> _encoderJs(
  JSString engineId,
  JSFloat32Array features,
);

@JS('window.fonnxKwsDecoder')
external JSPromise<JSFloat32Array> _decoderJs(
  JSString engineId,
  JSString contextsJson,
);

@JS('window.fonnxKwsJoiner')
external JSPromise<JSFloat32Array> _joinerJs(
  JSString engineId,
  JSFloat32Array encoder,
  JSFloat32Array decoder,
);

@JS('window.fonnxKwsReset')
external JSPromise<JSAny?> _resetJs(JSString engineId);

@JS('window.fonnxKwsClose')
external JSPromise<JSAny?> _closeJs(JSString engineId);

Future<KeywordSpotter> getKeywordSpotter({
  required KeywordSpotterBundle bundle,
  required List<KeywordPhrase> keywords,
  required int maxActivePaths,
  required int trailingBlankFrames,
}) async {
  final backend = WebKwsOnnxBackend();
  await backend.load(bundle);
  try {
    return KeywordSpotterWeb._(
      backend,
      keywords,
      maxActivePaths,
      trailingBlankFrames,
    );
  } catch (_) {
    await backend.close();
    rethrow;
  }
}

final class KeywordSpotterWeb extends KeywordSpotter {
  KeywordSpotterWeb._(
    WebKwsOnnxBackend backend,
    List<KeywordPhrase> keywords,
    int maxActivePaths,
    int trailingBlankFrames,
  ) : _engine = KeywordSpotterEngine(
        backend: backend,
        keywords: keywords,
        maxActivePaths: maxActivePaths,
        trailingBlankFrames: trailingBlankFrames,
      );

  final KeywordSpotterEngine _engine;
  final StreamController<KeywordDetection> _detections =
      StreamController<KeywordDetection>.broadcast(sync: true);
  var _closed = false;
  Future<void> _pending = Future<void>.value();

  @override
  Stream<KeywordDetection> get detections => _detections.stream;

  @override
  Future<void> acceptSamples(
    Float32List samples, {
    int sampleRate = 16000,
  }) async {
    _ensureOpen();
    final snapshot = Float32List.fromList(samples);
    return _enqueue(() async {
      for (final detection in await _engine.accept(
        snapshot,
        sampleRate: sampleRate,
      )) {
        _detections.add(detection);
      }
    });
  }

  @override
  Future<void> finish() async {
    _ensureOpen();
    return _enqueue(() async {
      for (final detection in await _engine.finish()) {
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
    final snapshot = Float32List.fromList(samples);
    return _enqueue(() => _engine.transcribe(snapshot, sampleRate: sampleRate));
  }

  @override
  Future<void> setKeywords(List<KeywordPhrase> keywords) {
    _ensureOpen();
    final snapshot = validatedKeywordPhraseSnapshot(keywords);
    return _enqueue(() => _engine.setKeywords(snapshot));
  }

  @override
  Future<void> reset() {
    _ensureOpen();
    return _enqueue(_engine.reset);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _enqueue(_engine.close);
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

final class WebKwsOnnxBackend implements KwsOnnxBackend {
  WebKwsOnnxBackend()
    : _engineId =
          'fonnx-kws-${DateTime.now().microsecondsSinceEpoch}-${_nextId++}';

  static var _nextId = 0;
  final String _engineId;

  Future<void> load(KeywordSpotterBundle bundle) async {
    await _loadJs(
      _engineId.toJS,
      bundle.encoderPath.toJS,
      bundle.decoderPath.toJS,
      bundle.joinerPath.toJS,
    ).toDart;
  }

  @override
  Future<KwsEncoderOutput> runEncoder(Float32List features) async {
    final values = (await _encoderJs(
      _engineId.toJS,
      features.toJS,
    ).toDart).toDart;
    return KwsEncoderOutput(
      values: Float32List.fromList(values),
      frameCount: values.length ~/ 320,
    );
  }

  @override
  Future<Float32List> runDecoder(Int64List tokenContexts) async {
    final json = jsonEncode(tokenContexts.toList(growable: false));
    final values = (await _decoderJs(_engineId.toJS, json.toJS).toDart).toDart;
    return Float32List.fromList(values);
  }

  @override
  Future<Float32List> runJoiner(
    Float32List encoderVectors,
    Float32List decoderVectors,
  ) async {
    final values = (await _joinerJs(
      _engineId.toJS,
      encoderVectors.toJS,
      decoderVectors.toJS,
    ).toDart).toDart;
    return Float32List.fromList(values);
  }

  @override
  Future<void> resetEncoderState() async {
    await _resetJs(_engineId.toJS).toDart;
  }

  @override
  Future<void> close() async {
    await _closeJs(_engineId.toJS).toDart;
  }
}
