import 'dart:js_interop';
import 'dart:typed_data';

import 'package:fonnx/models/msmarcoMiniLmL6V3/msmarco_mini_lm_l6_v3.dart';
import 'package:ml_linalg/linalg.dart';

MsmarcoMiniLmL6V3 getMsmarcoMiniLmL6V3(String path) =>
    MsmarcoMiniLmL6V3Web(path);

@JS('window.miniLmL6V2')
external JSPromise<JSAny?> sbertJs(JSString modelPath, JSInt16Array wordpieces);

class MsmarcoMiniLmL6V3Web implements MsmarcoMiniLmL6V3 {
  final String modelPath;

  MsmarcoMiniLmL6V3Web(this.modelPath);

  @override
  Future<Vector> getEmbeddingAsVector(List<int> tokens) async {
    final jsObject =
        await sbertJs(modelPath.toJS, Int16List.fromList(tokens).toJS).toDart;

    if (jsObject == null) {
      throw Exception('Embeddings returned from JS code are null');
    }
    final jsList = jsObject as JSFloat32Array;
    final vector = Vector.fromList(
      jsList.toDart,
      dtype: DType.float32,
    ).normalize();
    return vector;
  }
}
