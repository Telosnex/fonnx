import 'dart:typed_data';

import 'fonnx_platform_interface.dart';
export 'onnx/ort.dart';
export 'models/mini_lm_l6_v2.dart';

class Fonnx {
  Future<String?> getPlatformVersion() {
    return FonnxPlatform.instance.getPlatformVersion();
  }

  Future<Float32List?> miniLmL6V2({
    required String modelPath,
    required List<int> inputs,
  }) {
    return FonnxPlatform.instance.miniLmL6V2(
      modelPath: modelPath,
      inputs: inputs,
    );
  }
}
