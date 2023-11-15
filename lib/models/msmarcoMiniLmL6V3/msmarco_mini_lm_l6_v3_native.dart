import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:fonnx/fonnx.dart';
import 'package:fonnx/models/msmarcoMiniLmL6V3/msmarco_mini_lm_l6_v3.dart';
import 'package:fonnx/ort_manager.dart';
import 'package:fonnx/tokenizers/embedding.dart';
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

  Future<Float32List> getEmbedding(
      List<int> tokens) async {
    await _onnxIsolateManager.start();
    if (!kIsWeb && Platform.environment['FLUTTER_TEST'] == 'true') {
      return _onnxIsolateManager.sendInference(modelPath, tokens);
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return getEmbeddingViaPlatformChannel(tokens);
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return getEmbeddingViaFfi(tokens);
      case TargetPlatform.fuchsia:
        throw UnimplementedError();
    }
  }

  Future<Float32List> getEmbeddingViaFfi(List<int> tokens) {
    return _onnxIsolateManager.sendInference(modelPath, tokens);
  }

  Future<Float32List> getEmbeddingViaPlatformChannel(List<int> tokens) async {
    final fonnx = _fonnx ??= Fonnx();
    final embeddings = await fonnx.miniLmL6V2(
      modelPath: modelPath,
      inputs: tokens,
    );
    if (embeddings == null) {
      throw Exception('Embeddings returned from platform code are null');
    }
    return embeddings;
  }
}
