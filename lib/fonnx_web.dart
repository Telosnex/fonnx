import 'dart:typed_data';

import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import 'fonnx_platform_interface.dart';

/// A web implementation of the FonnxPlatform of the Fonnx plugin.
class FonnxWeb extends FonnxPlatform {
  /// Constructs a FonnxWeb
  FonnxWeb();

  static void registerWith(Registrar registrar) {
    FonnxPlatform.instance = FonnxWeb();
  }

  /// Returns a [String] containing the version of the platform.
  @override
  Future<String?> getPlatformVersion() async {
      throw UnimplementedError();
  }

  @override
  Future<Float32List?> miniLm({
    required String modelPath,
    required List<int> inputs,
  }) async {
      throw UnimplementedError();
  }
}
