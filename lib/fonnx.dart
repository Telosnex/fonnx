import 'dart:typed_data';

import 'fonnx_platform_interface.dart';
export 'extensions/vector.dart';
export 'models/whisper/whisper.dart';
export 'models/magika/magika.dart';

class Fonnx {
  Future<String?> getPlatformVersion() {
    return FonnxPlatform.instance.getPlatformVersion();
  }

  Future<Float32List> magika({
    required String modelPath,
    required List<int> bytes,
  }) {
    return FonnxPlatform.instance.magika(
      modelPath: modelPath,
      bytes: bytes,
    );
  }

  Future<Float32List?> miniLm({
    required String modelPath,
    required List<int> inputs,
  }) {
    return FonnxPlatform.instance.miniLm(
      modelPath: modelPath,
      inputs: inputs,
    );
  }

  Future<String?> whisper({
    required String modelPath,
    required List<int> audioBytes,
  }) {
    return FonnxPlatform.instance.whisper(
      modelPath: modelPath,
      audioBytes: audioBytes,
    );
  }

  Future<Map<String, dynamic>?> sileroVad({
    required String modelPath,
    required List<int> audioBytes,
    required Map<String, dynamic> previousState,
  }) {
    return FonnxPlatform.instance.sileroVad(
      modelPath: modelPath,
      audioBytes: audioBytes,
      previousState: previousState,
    );
  }

  Future<List<Map<String, dynamic>>?> pyannote({
    required String modelPath,
    required String modelName,
    required Float32List audioData,
    required double step,
  }) {
    return FonnxPlatform.instance.pyannote(
      modelPath: modelPath,
      modelName: modelName,
      audioData: audioData,
      step: step,
    );
  }
}
