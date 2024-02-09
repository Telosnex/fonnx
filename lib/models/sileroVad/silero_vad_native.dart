import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:fonnx/dylib_path_overrides.dart';
import 'package:fonnx/fonnx.dart';
import 'package:fonnx/models/sileroVad/silero_vad.dart';
import 'package:fonnx/models/sileroVad/silero_vad_isolate.dart';

SileroVad getSileroVad(String path) => SileroVadNative(path);

class SileroVadNative implements SileroVad {
  final SileroVadIsolateManager _sileroVadIsolateManager =
      SileroVadIsolateManager();

  @override
  final String modelPath;
  SileroVadNative(this.modelPath);

  @override
  Future<Float32List> doInference(List<int> bytes) async {
    await _sileroVadIsolateManager.start();
    if (!kIsWeb && Platform.environment['FLUTTER_TEST'] == 'true') {
      return _sileroVadIsolateManager.sendInference(
        modelPath,
        bytes,
        ortDylibPathOverride: fonnxOrtDylibPathOverride,
        ortExtensionsDylibPathOverride: fonnxOrtExtensionsDylibPathOverride,
      );
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return _getTranscriptPlatformChannel(bytes);
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return _getTranscriptFfi(bytes);
      case TargetPlatform.fuchsia:
        throw UnimplementedError();
    }
  }


  Future<Float32List> _getTranscriptFfi(List<int> audio) async {
    return _sileroVadIsolateManager.sendInference(
      modelPath,
      audio,
      ortDylibPathOverride: fonnxOrtDylibPathOverride,
    );
  }

  Future<Float32List> _getTranscriptPlatformChannel(
      List<int> audioBytes) async {
    throw UnimplementedError();
  }
}
