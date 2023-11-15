import 'dart:typed_data';

import 'package:fonnx/models/msmarcoMiniLmL6V3/msmarco_mini_lm_l6_v3.dart';
import 'package:fonnx/tokenizers/embedding.dart';
import 'package:js/js_util.dart';

import 'package:js/js.dart';

import 'package:ml_linalg/linalg.dart';

MsmarcoMiniLmL6V3 getMsmarcoMiniLmL6V3(String path) =>
    MsmarcoMiniLmL6V3Web(path);

@JS()
class Promise<T> {
  external Promise(
      void Function(void Function(T result) resolve, Function reject) executor);
  external Promise then(void Function(T result) onFulfilled,
      [Function onRejected]);
}

@JS('window.miniLmL6V2')
external Promise<List<List<double>>> sbertJs(
    String modelPath, List<int> wordpieces);

class MsmarcoMiniLmL6V3Web implements MsmarcoMiniLmL6V3 {
  final String modelPath;

  MsmarcoMiniLmL6V3Web(this.modelPath);

  @override
  Future<Vector> getEmbeddingAsVector(List<int> tokens) async {
    final jsObject = await promiseToFuture(sbertJs(modelPath, tokens));

    if (jsObject == null) {
      throw Exception('Embeddings returned from JS code are null');
    }

    final jsList = (jsObject as List<dynamic>);
    final vector = Vector.fromList(
      Float32List.fromList(jsList.cast()),
      dtype: DType.float32,
    ).normalize();
    return vector;
  }
}
