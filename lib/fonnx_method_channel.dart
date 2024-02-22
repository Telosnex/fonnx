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

  @override
  Future<Float32List> magika({
    required String modelPath,
    required List<int> bytes,
  }) async {
    final result = await methodChannel.invokeMethod<List<Object?>>(
      'magika',
      [modelPath, bytes],
    );
    final cast = result?.cast<double>();
    if (cast == null) {
      throw Exception('Invalid result from platform');
    }
    return Float32List.fromList(cast);
  }
  
  /// Create embeddings for [inputs].
  /// Inputs are BERT tokens. Use [WordpieceTokenizer] to convert a [String].
  @override
  Future<Float32List?> miniLm({
    required String modelPath,
    required List<int> inputs,
  }) async {
    final result = await methodChannel.invokeMethod<Float32List>(
      'miniLm',
      [modelPath, inputs],
    );
    return result;
  }

  @override
  Future<String?> whisper({
    required String modelPath,
    required List<int> audioBytes,
  }) async {
    final result = await methodChannel.invokeMethod<String>(
      'whisper',
      [modelPath, audioBytes],
    );
    return result;
  }

  @override
  Future<Map<String, dynamic>?> sileroVad({
    required String modelPath,
    required List<int> audioBytes,
    required Map<String, dynamic> previousState,
  }) async {
    final dynamic rawResult = await methodChannel.invokeMethod<dynamic>(
      'sileroVad',
      [modelPath, audioBytes, previousState],
    );

    // Check if the result is not null and is a Map, then cast it to the correct type
    if (rawResult != null && rawResult is Map) {
      // Casting each key and value to String and dynamic respectively
      // This step makes sure you're returning the correct type
      return rawResult
          .map<String, dynamic>((key, value) => MapEntry(key as String, value));
    }
    return null;
  }
}
