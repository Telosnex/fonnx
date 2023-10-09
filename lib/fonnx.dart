import 'fonnx_platform_interface.dart';
export 'onnx/ort.dart';
export 'models/mini_lm_l6_v2.dart';

class Fonnx {
  Future<String?> getPlatformVersion() {
    return FonnxPlatform.instance.getPlatformVersion();
  }
}
