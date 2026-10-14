import 'dart:js_interop';
import 'dart:typed_data';

import 'package:fonnx/extensions/uint8list.dart';
import 'package:fonnx/models/nemoAsr/nemo_asr.dart';
import 'package:fonnx/src/web_loader.dart';

import 'src/nemo_asr_engine.dart';

NemoAsr getNemoAsr(NemoAsrBundle bundle) => NemoAsrWeb(bundle);

@JS('window.fonnxNemoAsrLoad')
external JSPromise<JSAny?> _loadJs(
  JSString engineId,
  JSString kind,
  JSArray<JSString> paths,
  JSNumber blank,
);

@JS('window.fonnxNemoAsrEncode')
external JSPromise<JSFloat32Array> _encodeJs(
  JSString engineId,
  JSFloat32Array features,
  JSNumber frames,
);

@JS('window.fonnxNemoAsrJoint')
external JSPromise<JSFloat32Array> _jointJs(JSString engineId, JSNumber frame);

@JS('window.fonnxNemoAsrPredict')
external JSPromise<JSAny?> _predictJs(JSString engineId, JSNumber token);

@JS('window.fonnxNemoAsrClose')
external JSPromise<JSAny?> _closeJs(JSString engineId);

/// NemoAsr on web. The ORT sessions, the encoder output and the prediction
/// network's state live in a Web Worker. The features and the decoding run
/// here, in the same Dart code as native.
class NemoAsrWeb implements NemoAsr {
  NemoAsrWeb(this.bundle);

  @override
  final NemoAsrBundle bundle;

  final _backend = WebNemoAsrOnnxBackend();
  late final _engine = NemoAsrEngine(_backend, bundle.model);
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

  /// Runs one transcription at a time; each one uses the decoder state.
  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final result = _pending.then((_) => operation());
    _pending = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }
}

final class WebNemoAsrOnnxBackend implements NemoAsrOnnxBackend {
  WebNemoAsrOnnxBackend()
    : _engineId =
          'fonnx-nemo-asr-${DateTime.now().microsecondsSinceEpoch}-${_nextId++}';

  static var _nextId = 0;
  final String _engineId;

  Future<void> load(NemoAsrBundle bundle) async {
    await loadFonnxWebModule('nemo_asr_init.js');
    await _loadJs(
      _engineId.toJS,
      switch (bundle.model) {
        NemoAsrModel.fastConformerCtcMultilingual => 'ctc',
        NemoAsrModel.parakeetTdtV3 => 'tdt',
      }.toJS,
      [for (final path in bundle.paths) path.toJS].toJS,
      parakeetTdtV3Blank.toJS,
    ).toDart;
  }

  @override
  Future<Float32List> encode(Float32List features, int frames) async =>
      (await _encodeJs(
        _engineId.toJS,
        features.toJS,
        frames.toJS,
      ).toDart).toDart;

  @override
  Future<Float32List> joint(int frame) async =>
      (await _jointJs(_engineId.toJS, frame.toJS).toDart).toDart;

  @override
  Future<void> predict(int token) async {
    await _predictJs(_engineId.toJS, token.toJS).toDart;
  }

  @override
  Future<void> close() async {
    await _closeJs(_engineId.toJS).toDart;
  }
}
