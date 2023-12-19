import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:fonnx/dylib_path_overrides.dart';
import 'package:fonnx/fonnx.dart';
import 'package:fonnx/models/msmarcoMiniLmL6V3/msmarco_mini_lm_l6_v3.dart';
import 'package:fonnx/ort_minilm_isolate.dart';
import 'package:ml_linalg/linalg.dart';

MsmarcoMiniLmL6V3 getMsmarcoMiniLmL6V3(String path) =>
    MsmarcoMiniLmL6V3Native(path);

class MsmarcoMiniLmL6V3Native implements MsmarcoMiniLmL6V3 {
  final String modelPath;
  final OnnxIsolateManager _onnxIsolateManager = OnnxIsolateManager();

  MsmarcoMiniLmL6V3Native(this.modelPath);

  Fonnx? _fonnx;

  @override
  Future<Vector> getEmbeddingAsVector(List<int> tokens) async {
    final embeddings = await getEmbedding(tokens);
    final vector =
        Vector.fromList(embeddings, dtype: DType.float32).normalize();
    return vector;
  }

  Future<Float32List> getEmbedding(List<int> tokens) async {
    final ffiPlatform =
        !kIsWeb && Platform.isLinux || Platform.isMacOS || Platform.isWindows;
    final platformChannelPlatform =
        !kIsWeb && Platform.isAndroid || Platform.isIOS;
    if (ffiPlatform) {
      await _onnxIsolateManager.start();
      return getEmbeddingViaFfi(tokens);
    } else if (platformChannelPlatform) {
      return getEmbeddingViaPlatformChannel(tokens);
    } else {
      throw UnimplementedError(
          'Unsupported platform: ${Platform.operatingSystem}');
    }
  }

  Future<Float32List> getEmbeddingViaFfi(List<int> tokens) {
    return _onnxIsolateManager.sendInference(
      modelPath,
      tokens,
      ortDylibPathOverride: fonnxOrtDylibPathOverride,
    );
  }

  Future<Float32List> getEmbeddingViaPlatformChannel(List<int> tokens) async {
    final fonnx = _fonnx ??= Fonnx();
    final embeddings = await fonnx.miniLm(
      modelPath: modelPath,
      inputs: tokens,
    );
    if (embeddings == null) {
      throw Exception('Embeddings returned from platform code are null');
    }
    return embeddings;
  }
}
