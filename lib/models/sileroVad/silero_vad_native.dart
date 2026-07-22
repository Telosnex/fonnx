import 'dart:typed_data';

import 'package:fonnx/dylib_path_overrides.dart';
import 'package:fonnx/models/sileroVad/silero_vad.dart';
import 'package:fonnx/models/sileroVad/silero_vad_isolate.dart';

SileroVad getSileroVad(String path) => SileroVadNative(path);

class SileroVadNative implements SileroVad {
  SileroVadNative(this.modelPath);

  final SileroVadIsolateManager _sileroVadIsolateManager =
      SileroVadIsolateManager();

  @override
  final String modelPath;

  @override
  Future<Map<String, dynamic>> doInference(
    Uint8List bytes, {
    Map<String, dynamic> previousState = const {},
  }) async {
    await _sileroVadIsolateManager.start();
    return _sileroVadIsolateManager.sendInference(
      modelPath,
      bytes,
      previousState,
      ortDylibPathOverride: fonnxOrtDylibPathOverride,
    );
  }
}
