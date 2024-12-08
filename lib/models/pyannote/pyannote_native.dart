import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:fonnx/dylib_path_overrides.dart';
import 'package:fonnx/fonnx.dart';
import 'package:fonnx/models/pyannote/pyannote_isolate.dart';

Pyannote getPyannote(String path) => PyannoteNative(path);

class PyannoteNative implements Pyannote {
  final PyannoteIsolateManager _pyannoteIsolateManager = PyannoteIsolateManager();
  Fonnx? _fonnx;

  @override
  final String modelPath;


  PyannoteNative(this.modelPath);

  @override
  Future<List<Map<String, dynamic>>> process(Float32List audioData, {double? step}) async {
    await _pyannoteIsolateManager.start();
    if (!kIsWeb && Platform.environment['FLUTTER_TEST'] == 'true') {
      return _pyannoteIsolateManager.sendInference(
        modelPath,
        audioData,
        ortDylibPathOverride: fonnxOrtDylibPathOverride,
      );
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return _processPlatformChannel(audioData);
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return _processFfi(audioData);
      case TargetPlatform.fuchsia:
        throw UnimplementedError();
    }
  }

  Future<List<Map<String, dynamic>>> _processFfi(Float32List audioData) async {
    return _pyannoteIsolateManager.sendInference(
      modelPath,
      audioData,
      ortDylibPathOverride: fonnxOrtDylibPathOverride,
    );
  }

  Future<List<Map<String, dynamic>>> _processPlatformChannel(Float32List audioData) async {
    final fonnx = _fonnx ??= Fonnx();
    final result = await fonnx.pyannote(
      modelPath: modelPath,
      audioData: audioData,
    );
    if (result == null) {
      throw Exception('Result returned from platform code is null');
    }
    return result;
  }
}