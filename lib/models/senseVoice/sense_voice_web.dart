import 'dart:js_interop';
import 'dart:typed_data';

import 'package:fonnx/extensions/uint8list.dart';
import 'package:fonnx/models/senseVoice/sense_voice.dart';
import 'package:fonnx/src/web_loader.dart';

import 'src/sense_voice_engine.dart';

SenseVoice getSenseVoice(SenseVoiceBundle bundle) => SenseVoiceWeb(bundle);

@JS('window.fonnxSenseVoiceLoad')
external JSPromise<JSAny?> _loadJs(JSString engineId, JSString path);

@JS('window.fonnxSenseVoiceRun')
external JSPromise<JSFloat32Array> _runJs(
  JSString engineId,
  JSFloat32Array features,
  JSNumber frames,
  JSNumber language,
  JSNumber textNorm,
);

@JS('window.fonnxSenseVoiceClose')
external JSPromise<JSAny?> _closeJs(JSString engineId);

@JS('fetch')
external JSPromise<_Response> _fetch(JSString url);

extension type _Response._(JSObject _) implements JSObject {
  external bool get ok;
  external int get status;
  external JSPromise<JSString> text();
}

/// SenseVoice on web. The ORT session lives in a Web Worker. The features and
/// the decoding run here, in the same Dart code as native.
class SenseVoiceWeb implements SenseVoice {
  SenseVoiceWeb(this.bundle);

  @override
  final SenseVoiceBundle bundle;

  final _backend = WebSenseVoiceOnnxBackend();
  Future<SenseVoiceEngine>? _engine;
  Future<void> _pending = Future<void>.value();

  @override
  Future<String> doInference(
    Uint8List bytes, {
    SenseVoiceLanguage language = SenseVoiceLanguage.auto,
  }) {
    final samples = bytes.toAudioFloat32List();
    return _enqueue(() async {
      final engine = await (_engine ??= _load().catchError((Object error) {
        _engine = null;
        throw error;
      }));
      return engine.transcribe(samples, language);
    });
  }

  Future<SenseVoiceEngine> _load() async {
    final response = await _fetch(bundle.tokensPath.toJS).toDart;
    if (!response.ok) {
      throw StateError(
        'SenseVoice tokens ${bundle.tokensPath}: HTTP ${response.status}',
      );
    }
    final tokens = parseSenseVoiceTokens((await response.text().toDart).toDart);
    await _backend.load(bundle.modelPath);
    return SenseVoiceEngine(_backend, tokens);
  }

  /// Runs one transcription at a time.
  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final result = _pending.then((_) => operation());
    _pending = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }
}

final class WebSenseVoiceOnnxBackend implements SenseVoiceOnnxBackend {
  WebSenseVoiceOnnxBackend()
    : _engineId =
          'fonnx-sense-voice-${DateTime.now().microsecondsSinceEpoch}-${_nextId++}';

  static var _nextId = 0;
  final String _engineId;

  Future<void> load(String modelPath) async {
    await loadFonnxWebModule('sense_voice_init.js');
    await _loadJs(_engineId.toJS, modelPath.toJS).toDart;
  }

  @override
  Future<Float32List> run(
    Float32List features,
    int frames,
    int language,
  ) async => (await _runJs(
    _engineId.toJS,
    features.toJS,
    frames.toJS,
    language.toJS,
    senseVoiceWithItn.toJS,
  ).toDart).toDart;

  @override
  Future<void> close() async {
    await _closeJs(_engineId.toJS).toDart;
  }
}
