import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:fonnx/dylib_path_overrides.dart';
import 'package:fonnx/fonnx.dart';
import 'package:fonnx/models/pyannote/pyannote.dart';
import 'package:fonnx/models/pyannote/pyannote_isolate.dart';

Pyannote getPyannote(String path, String modelName) => PyannoteNative(path, modelName);

class PyannoteNative implements Pyannote {
  final PyannoteIsolateManager _pyannoteIsolateManager = PyannoteIsolateManager();
  Fonnx? _fonnx;

  @override
  final String modelPath;

  @override
  final String modelName;

  PyannoteNative(this.modelPath, this.modelName);

  @override
  Future<List<Map<String, dynamic>>> process(Float32List audioData, {double? step}) async {
    await _pyannoteIsolateManager.start();
    if (!kIsWeb && Platform.environment['FLUTTER_TEST'] == 'true') {
      return _pyannoteIsolateManager.sendInference(
        modelPath,
        audioData,
        {
          'modelName': modelName,
          'numSpeakers': 2,
          'duration': 10.0,
        },
        ortDylibPathOverride: fonnxOrtDylibPathOverride,
      );
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return _processPlatformChannel(audioData, step);
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return _processFfi(audioData, step);
      case TargetPlatform.fuchsia:
        throw UnimplementedError();
    }
  }

  Future<List<Map<String, dynamic>>> _processFfi(Float32List audioData, double? step) async {
    return _pyannoteIsolateManager.sendInference(
      modelPath,
      audioData,
      {
        'modelName': modelName,
        'step': step,
      },
      ortDylibPathOverride: fonnxOrtDylibPathOverride,
    );
  }

  Future<List<Map<String, dynamic>>> _processPlatformChannel(Float32List audioData, double? step) async {
    final fonnx = _fonnx ??= Fonnx();
    final result = await fonnx.pyannote(
      modelPath: modelPath,
      modelName: modelName,
      audioData: audioData,
      step: step ?? 0.0,
    );
    if (result == null) {
      throw Exception('Result returned from platform code is null');
    }
    return result;
  }
}