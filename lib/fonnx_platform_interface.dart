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

  Future<Float32List> magika({
    required String modelPath,
    required List<int> bytes,
  }) {
    throw UnimplementedError('magika() has not been implemented.');
  }

  Future<Float32List?> miniLm({
    required String modelPath,
    required List<int> inputs,
  }) {
    throw UnimplementedError('miniLm() has not been implemented.');
  }

  Future<List<Map<String, dynamic>>?> pyannote({
    required String modelPath,
    required Float32List audioData,
  }) {
    throw UnimplementedError('pyannote() has not been implemented.');
  }

  Future<String?> whisper({
    required String modelPath,
    required List<int> audioBytes,
  }) async {
    throw UnimplementedError('whisper() has not been implemented.');
  }

  Future<Map<String, dynamic>?> sileroVad({
    required String modelPath,
    required List<int> audioBytes,
    required Map<String, dynamic> previousState,
  }) async {
    throw UnimplementedError('sileroVad() has not been implemented.');
  }
}
