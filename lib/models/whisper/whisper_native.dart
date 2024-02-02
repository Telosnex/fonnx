
import 'package:flutter/foundation.dart';
import 'package:fonnx/dylib_path_overrides.dart';

import 'package:fonnx/models/whisper/whisper.dart';
import 'package:fonnx/models/whisper/whisper_isolate.dart';

Whisper getWhisper(String path) => WhisperNative(path);

class WhisperNative implements Whisper {
    final WhisperIsolateManager _whisperIsolateManager = WhisperIsolateManager();

  @override
  final String modelPath;
  WhisperNative(this.modelPath);

  @override
  Future<String> doInference(Uint8List bytes) {
    return _getTranscriptFfi(bytes);
  }


  Future<String> _getTranscriptFfi(Uint8List audio) async {
    return _whisperIsolateManager.sendInference(
      modelPath,
      audio,
      ortDylibPathOverride: fonnxOrtDylibPathOverride,
    );
  }
}
