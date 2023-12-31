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
}
