import 'dart:typed_data';

import 'package:fonnx/extensions/uint8list.dart';
import 'package:fonnx/models/whisper/whisper.dart';
import 'package:fonnx/models/whisper/whisper_isolate.dart';

Whisper getWhisper(WhisperBundle bundle) => WhisperNative(bundle);

class WhisperNative implements Whisper {
  WhisperNative(this.bundle);

  final WhisperIsolateManager _manager = WhisperIsolateManager();
  Future<void> _pending = Future<void>.value();

  @override
  final WhisperBundle bundle;

  @override
  Future<String> doInference(Uint8List bytes) {
    final samples = bytes.toAudioFloat32List();
    return _enqueue(() async {
      await _manager.start(bundle);
      return _manager.transcribe(samples);
    });
  }

  /// Runs one transcription at a time; each one uses the whole cache.
  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final result = _pending.then((_) => operation());
    _pending = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }
}
