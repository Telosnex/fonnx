import 'dart:typed_data';

import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import 'fonnx_platform_interface.dart';

/// A web implementation of the FonnxPlatform of the Fonnx plugin.
/// 
/// This is intentionally unimplemented: on web, inference should be implemented
/// using a JavaScript worker that uses the ONNX Runtime WebAssembly backend.*
/// See index.html and worker.js in example/web.
/// 
/// * or, optionally, WebGPU / WebGL. They don't seem to be fully fleshed out
/// yet, testing with Mini LM models led to errors as of 2024 Jan 2nd.
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
