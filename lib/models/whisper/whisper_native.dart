import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:fonnx/dylib_path_overrides.dart';
import 'package:fonnx/fonnx.dart';

import 'package:fonnx/models/whisper/whisper_isolate.dart';

Whisper getWhisper(String path) => WhisperNative(path);

class WhisperNative implements Whisper {
  final WhisperIsolateManager _whisperIsolateManager = WhisperIsolateManager();
  Fonnx? _fonnx;

  @override
  final String modelPath;
  WhisperNative(this.modelPath);

  @override
  Future<String> doInference(List<int> bytes) async {
    await _whisperIsolateManager.start();
    if (!kIsWeb && Platform.environment['FLUTTER_TEST'] == 'true') {
      return _getTranscriptFfi(bytes);
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

  Future<String> _getTranscriptFfi(List<int> audio) async {
    final answer = await _whisperIsolateManager.sendInference(
      modelPath,
      audio,
      ortDylibPathOverride: fonnxOrtDylibPathOverride,
    );
    return Whisper.removeTimestamps(answer);
  }

  Future<String> _getTranscriptPlatformChannel(List<int> audioBytes) async {
    final fonnx = _fonnx ??= Fonnx();
    final answer = await fonnx.whisper(
      modelPath: modelPath,
      audioBytes: audioBytes,
    );
    if (answer == null) {
      throw Exception('Transcript returned from platform code is null');
    }
    return Whisper.removeTimestamps(answer);
  }
}
