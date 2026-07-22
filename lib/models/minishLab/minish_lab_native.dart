import 'dart:typed_data';

import 'package:fonnx/models/minishLab/minish_lab.dart';
import 'package:fonnx/ort_minilm_isolate.dart';
import 'package:ml_linalg/linalg.dart';

MinishLab getMinishLab(String path) => MinishLabNative(path);

class MinishLabNative implements MinishLab {
  MinishLabNative(this.modelPath);

  final String modelPath;
  final OnnxIsolateManager _onnxIsolateManager = OnnxIsolateManager();

  @override
  Future<Vector> getEmbeddingAsVector(List<int> tokens) async {
    final embeddings = await getEmbedding(tokens);
    return Vector.fromList(embeddings, dtype: DType.float32).normalize();
  }

  Future<Float32List> getEmbedding(List<int> tokens) async {
    await _onnxIsolateManager.start(OnnxIsolateType.minishLab);
    return _onnxIsolateManager.sendInference(modelPath, tokens);
  }
}
