import 'dart:typed_data';

import 'package:fonnx/dylib_path_overrides.dart';
import 'package:fonnx/models/msmarcoMiniLmL6V3/msmarco_mini_lm_l6_v3.dart';
import 'package:fonnx/ort_minilm_isolate.dart';
import 'package:ml_linalg/linalg.dart';

MsmarcoMiniLmL6V3 getMsmarcoMiniLmL6V3(String path) =>
    MsmarcoMiniLmL6V3Native(path);

class MsmarcoMiniLmL6V3Native implements MsmarcoMiniLmL6V3 {
  MsmarcoMiniLmL6V3Native(this.modelPath);

  final String modelPath;
  final OnnxIsolateManager _onnxIsolateManager = OnnxIsolateManager();

  @override
  Future<Vector> getEmbeddingAsVector(List<int> tokens) async {
    final embeddings = await getEmbedding(tokens);
    return Vector.fromList(embeddings, dtype: DType.float32).normalize();
  }

  Future<Float32List> getEmbedding(List<int> tokens) async {
    await _onnxIsolateManager.start(OnnxIsolateType.miniLm);
    return _onnxIsolateManager.sendInference(
      modelPath,
      tokens,
      ortDylibPathOverride: fonnxOrtDylibPathOverride,
    );
  }
}
