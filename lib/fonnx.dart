import 'dart:typed_data';

import 'fonnx_platform_interface.dart';
export 'extensions/vector.dart';
export 'onnx/ort.dart';
export 'models/minilml6v2/mini_lm_l6_v2_native.dart';
export 'models/whisper/whisper.dart';

class Fonnx {
  Future<String?> getPlatformVersion() {
    return FonnxPlatform.instance.getPlatformVersion();
  }

  Future<Float32List?> miniLm({
    required String modelPath,
    required List<int> inputs,
  }) {
    return FonnxPlatform.instance.miniLm(
      modelPath: modelPath,
      inputs: inputs,
    );
  }

  Future<String?> whisper({
    required String modelPath,
    required List<int> audioBytes,
  }) {
    return FonnxPlatform.instance.whisper(
      modelPath: modelPath,
      audioBytes: audioBytes,
    );
  }

  Future<Map<String, dynamic>?> sileroVad({
    required String modelPath,
    required List<int> audioBytes,
    required Map<String, dynamic> previousState,
  }) {
    return FonnxPlatform.instance.sileroVad(
      modelPath: modelPath,
      audioBytes: audioBytes,
      previousState: previousState,
    );
  }
}
