
import 'fonnx_platform_interface.dart';

class Fonnx {
  Future<String?> getPlatformVersion() {
    return FonnxPlatform.instance.getPlatformVersion();
  }
}
