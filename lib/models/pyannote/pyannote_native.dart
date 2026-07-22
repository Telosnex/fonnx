import 'dart:typed_data';

import 'package:fonnx/dylib_path_overrides.dart';
import 'package:fonnx/models/pyannote/pyannote.dart';
import 'package:fonnx/models/pyannote/pyannote_isolate.dart';

Pyannote getPyannote(String path) => PyannoteNative(path);

class PyannoteNative implements Pyannote {
  PyannoteNative(this.modelPath);

  final PyannoteIsolateManager _pyannoteIsolateManager =
      PyannoteIsolateManager();

  @override
  final String modelPath;

  @override
  Future<List<Map<String, dynamic>>> process(
    Float32List audioData, {
    double? step,
  }) async {
    await _pyannoteIsolateManager.start();
    return _pyannoteIsolateManager.sendInference(
      modelPath,
      audioData,
      ortDylibPathOverride: fonnxOrtDylibPathOverride,
    );
  }
}
