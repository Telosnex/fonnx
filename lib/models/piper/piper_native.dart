import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:fonnx/fonnx.dart';
import 'package:fonnx/models/piper/piper.dart';
import 'package:fonnx/piper/piper_isolate.dart';
import 'package:fonnx/piper/piper_models.dart';

Piper getPiper(String path) => PiperNative(path);

class PiperNative implements Piper {
  final String modelPath;

  PiperNative(this.modelPath);

  final PiperIsolateManager _onnxIsolateManager = PiperIsolateManager();

  Fonnx? _fonnx;

  Future<Float32List> getTts(
      {required PiperConfig config, required List<int> phonemes}) async {
    await _onnxIsolateManager.start();
    final synthesisConfig = PiperSynthesisConfig(
      noiseScale: config.inference!.noiseScale!,
      lengthScale: config.inference!.lengthScale!,
      noiseW: config.inference!.noiseW!,
      speakerId: 0,
    );
    if (!kIsWeb && Platform.environment['FLUTTER_TEST'] == 'true') {
      return _onnxIsolateManager.sendInference(
        modelPath,
        synthesisConfig,
        phonemes,
      );
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return getTtsViaPlatformChannel(
          phonemes,
          config.inference!.noiseScale!,
          config.inference!.lengthScale!,
          config.inference!.noiseW!,
        );
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return getTtsViaFfi(phonemes, synthesisConfig);
      case TargetPlatform.fuchsia:
        throw UnimplementedError();
    }
  }

  Future<Float32List> getTtsViaFfi(
    List<int> phonemeIds,
    PiperSynthesisConfig config,
  ) {
    return _onnxIsolateManager.sendInference(
      modelPath,
      config,
      phonemeIds,
    );
  }

  Future<Float32List> getTtsViaPlatformChannel(
    List<int> phonemeIds,
    double noiseScale,
    double lengthScale,
    double noiseW,
  ) async {
    throw UnimplementedError();
  }
}
