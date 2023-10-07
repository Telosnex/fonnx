import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'fonnx_platform_interface.dart';

/// An implementation of [FonnxPlatform] that uses method channels.
class MethodChannelFonnx extends FonnxPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('fonnx');

  @override
  Future<String?> getPlatformVersion() async {
    final version =
        await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }

  /// Create embeddings for [texts].
  /// https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2
  Future<List<List<double>>?> miniLmL6V2(List<String> texts) async {
    final result = await methodChannel
        .invokeMethod<List<List<double>>>('miniLmL6V2');
    return result;
  }
}
