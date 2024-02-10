import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:fonnx/dylib_path_overrides.dart';
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
  Future<Map<String, dynamic>> doInference(Uint8List bytes,
      {Map<String, dynamic> previousState = const {}}) async {
    await _sileroVadIsolateManager.start();
    if (!kIsWeb && Platform.environment['FLUTTER_TEST'] == 'true') {
      return _sileroVadIsolateManager.sendInference(
        modelPath,
        bytes,
        previousState,
        ortDylibPathOverride: fonnxOrtDylibPathOverride,
        ortExtensionsDylibPathOverride: fonnxOrtExtensionsDylibPathOverride,
      );
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return _getTranscriptPlatformChannel(bytes, previousState);
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return _getTranscriptFfi(bytes, previousState);
      case TargetPlatform.fuchsia:
        throw UnimplementedError();
    }
  }


  Future<Map<String, dynamic>> _getTranscriptFfi(
    List<int> audio,
    Map<String, dynamic> previousState,
  ) async {
    return _sileroVadIsolateManager.sendInference(
      modelPath,
      audio,
      previousState,
      ortDylibPathOverride: fonnxOrtDylibPathOverride,
    );
  }

  Future<Map<String, dynamic>> _getTranscriptPlatformChannel(
    List<int> audioBytes,
    Map<String, dynamic> previousState,
  ) async {
    throw UnimplementedError();
  }
}
