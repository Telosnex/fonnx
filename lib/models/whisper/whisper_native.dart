import 'dart:typed_data';

import 'package:fonnx/dylib_path_overrides.dart';
import 'package:fonnx/models/whisper/whisper.dart';
import 'package:fonnx/models/whisper/whisper_isolate.dart';

Whisper getWhisper(String path) => WhisperNative(path);

class WhisperNative implements Whisper {
  WhisperNative(this.modelPath);

  final WhisperIsolateManager _whisperIsolateManager = WhisperIsolateManager();

  @override
  final String modelPath;

  @override
  Future<String> doInference(List<int> bytes) async {
    final snapshot = Uint8List.fromList(bytes);
    await _whisperIsolateManager.start();
    final answer = await _whisperIsolateManager.sendInference(
      modelPath,
      snapshot,
      ortDylibPathOverride: fonnxOrtDylibPathOverride,
      ortExtensionsDylibPathOverride: fonnxOrtExtensionsDylibPathOverride,
    );
    return Whisper.removeTimestamps(answer);
  }
}
