import 'dart:js_interop';
import 'dart:typed_data';

import 'package:fonnx/models/minilml6v2/mini_lm_l6_v2.dart';
import 'package:ml_linalg/linalg.dart';

MiniLmL6V2 getMiniLmL6V2(String path) => MiniLmL6V2Web(path);

@JS('window.miniLmL6V2')
external JSPromise<JSAny?> sbertJs(
    String modelPath, List<int> wordpieces);

class MiniLmL6V2Web implements MiniLmL6V2 {
  final String modelPath;

  MiniLmL6V2Web(this.modelPath);

  @override
  Future<Vector> getEmbeddingAsVector(List<int> tokens) async {
    final jsObject = await sbertJs(modelPath, tokens).toDart;

    if (jsObject == null) {
      throw Exception('Embeddings returned from JS code are null');
    }

    final jsList = jsObject as List<dynamic>;
    final vector = Vector.fromList(
      Float32List.fromList(jsList.cast()),
      dtype: DType.float32,
    ).normalize();
    return vector;
  }
}
