import 'dart:js_interop';
import 'dart:typed_data';

import 'package:fonnx/models/minishLab/minish_lab.dart';
import 'package:ml_linalg/linalg.dart';

MinishLab getMinishLab(String path) => MinishLabWeb(path);

@JS('window.miniLmL6V2')
external JSPromise<JSAny?> sbertJs(JSString modelPath, JSInt16Array wordpieces);

class MinishLabWeb implements MinishLab {
  final String modelPath;

  MinishLabWeb(this.modelPath);

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
