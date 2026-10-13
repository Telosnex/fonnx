import 'dart:js_interop';
import 'dart:typed_data';

import 'package:fonnx/extensions/uint8list.dart';
import 'package:fonnx/models/whisper/whisper.dart';
import 'package:fonnx/src/web_loader.dart';

import 'src/whisper_engine.dart';

Whisper getWhisper(WhisperBundle bundle) => WhisperWeb(bundle);

@JS('window.fonnxWhisperLoad')
external JSPromise<JSAny?> _loadJs(
  JSString engineId,
  JSString encoderPath,
  JSString decoderPath,
  JSNumber layers,
  JSNumber heads,
);

@JS('window.fonnxWhisperEncode')
external JSPromise<JSAny?> _encodeJs(
  JSString engineId,
  JSFloat32Array features,
  JSNumber batch,
);

@JS('window.fonnxWhisperDecode')
external JSPromise<JSFloat32Array> _decodeJs(
  JSString engineId,
  JSInt32Array tokens,
  JSNumber length,
  JSInt32Array? parents,
);

@JS('window.fonnxWhisperClose')
external JSPromise<JSAny?> _closeJs(JSString engineId);

/// Whisper on web. The ORT sessions and the key/value cache live in a Web
/// Worker. The log-mel features and the beam search run here, in the same
/// Dart code as native.
class WhisperWeb implements Whisper {
  WhisperWeb(this.bundle);

  @override
  final WhisperBundle bundle;

  final _backend = WebWhisperOnnxBackend();
  late final _engine = WhisperEngine(_backend);
  Future<void>? _loading;
  Future<void> _pending = Future<void>.value();

  @override
  Future<String> doInference(Uint8List bytes) {
    final samples = bytes.toAudioFloat32List();
    return _enqueue(() async {
      await (_loading ??= _backend.load(bundle).catchError((Object error) {
        _loading = null;
        throw error;
      }));
      return _engine.transcribe(samples);
    });
  }

  /// Runs one transcription at a time; each one uses the whole cache.
  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final result = _pending.then((_) => operation());
    _pending = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }
}

final class WebWhisperOnnxBackend implements WhisperOnnxBackend {
  WebWhisperOnnxBackend()
    : _engineId =
          'fonnx-whisper-${DateTime.now().microsecondsSinceEpoch}-${_nextId++}';

  static var _nextId = 0;
  final String _engineId;

  Future<void> load(WhisperBundle bundle) async {
    await loadFonnxWebModule('whisper_init.js');
    await _loadJs(
      _engineId.toJS,
      bundle.encoderPath.toJS,
      bundle.decoderPath.toJS,
      bundle.decoderLayers.toJS,
      bundle.attentionHeads.toJS,
    ).toDart;
  }

  @override
  Future<void> encode(Float32List features, int batch) async {
    await _encodeJs(_engineId.toJS, features.toJS, batch.toJS).toDart;
  }

  @override
  Future<Float32List> decode(
    Int32List tokens,
    int length,
    Int32List? parents,
  ) async {
    final logits = await _decodeJs(
      _engineId.toJS,
      tokens.toJS,
      length.toJS,
      parents?.toJS,
    ).toDart;
    return logits.toDart;
  }

  @override
  Future<void> close() async {
    await _closeJs(_engineId.toJS).toDart;
  }
}
