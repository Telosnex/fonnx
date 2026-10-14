import 'dart:typed_data';

import 'package:fonnx/extensions/uint8list.dart';
import 'package:fonnx/models/senseVoice/sense_voice.dart';
import 'package:fonnx/models/senseVoice/sense_voice_isolate.dart';

SenseVoice getSenseVoice(SenseVoiceBundle bundle) => SenseVoiceNative(bundle);

class SenseVoiceNative implements SenseVoice {
  SenseVoiceNative(this.bundle);

  final SenseVoiceIsolateManager _manager = SenseVoiceIsolateManager();
  Future<void> _pending = Future<void>.value();

  @override
  final SenseVoiceBundle bundle;

  @override
  Future<String> doInference(
    Uint8List bytes, {
    SenseVoiceLanguage language = SenseVoiceLanguage.auto,
  }) {
    final samples = bytes.toAudioFloat32List();
    return _enqueue(() async {
      await _manager.start(bundle);
      return _manager.transcribe(samples, language);
    });
  }

  /// Runs one transcription at a time in the isolate.
  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final result = _pending.then((_) => operation());
    _pending = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }
}
