import 'dart:typed_data';

import 'package:fonnx/extensions/uint8list.dart';
import 'package:fonnx/models/nemoAsr/nemo_asr.dart';
import 'package:fonnx/models/nemoAsr/nemo_asr_isolate.dart';

NemoAsr getNemoAsr(NemoAsrBundle bundle) => NemoAsrNative(bundle);

class NemoAsrNative implements NemoAsr {
  NemoAsrNative(this.bundle);

  final NemoAsrIsolateManager _manager = NemoAsrIsolateManager();
  Future<void> _pending = Future<void>.value();

  @override
  final NemoAsrBundle bundle;

  @override
  Future<String> doInference(Uint8List bytes) {
    final samples = bytes.toAudioFloat32List();
    return _enqueue(() async {
      await _manager.start(bundle);
      return _manager.transcribe(samples);
    });
  }

  /// Runs one transcription at a time; each one uses the decoder state.
  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final result = _pending.then((_) => operation());
    _pending = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }
}
