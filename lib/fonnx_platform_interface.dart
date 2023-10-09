import 'dart:typed_data';

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'fonnx_method_channel.dart';

abstract class FonnxPlatform extends PlatformInterface {
  /// Constructs a FonnxPlatform.
  FonnxPlatform() : super(token: _token);

  static final Object _token = Object();

  static FonnxPlatform _instance = MethodChannelFonnx();

  /// The default instance of [FonnxPlatform] to use.
  ///
  /// Defaults to [MethodChannelFonnx].
  static FonnxPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FonnxPlatform] when
  /// they register themselves.
  static set instance(FonnxPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
  
  Future<List<Float32List>?> miniLmL6V2({
    required String modelPath,
    required List<List<int>> inputs,
  }) {
    throw UnimplementedError('miniLmL6V2() has not been implemented.');
  }
}
