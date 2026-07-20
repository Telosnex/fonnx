import 'dart:typed_data';

import 'package:fonnx/models/minilml6v2/mini_lm_l6_v2.dart';
import 'package:fonnx/ort_minilm_isolate.dart';
import 'package:ml_linalg/linalg.dart';

MiniLmL6V2 getMiniLmL6V2(String path) => MiniLmL6V2Native(path);

class MiniLmL6V2Native implements MiniLmL6V2 {
  MiniLmL6V2Native(this.modelPath);

  final String modelPath;
  final OnnxIsolateManager _onnxIsolateManager = OnnxIsolateManager();

  @override
  Future<Vector> getEmbeddingAsVector(List<int> tokens) async {
    final embeddings = await getEmbedding(tokens);
    return Vector.fromList(embeddings, dtype: DType.float32).normalize();
  }

  Future<Float32List> getEmbedding(List<int> tokens) async {
    await _onnxIsolateManager.start(OnnxIsolateType.miniLm);
    return _onnxIsolateManager.sendInference(modelPath, tokens);
  }
}
