import 'fonnx_platform_interface.dart';
export 'ort_ffi_bindings.dart';

class Fonnx {
  Future<String?> getPlatformVersion() {
    return FonnxPlatform.instance.getPlatformVersion();
  }
}
