import 'dart:typed_data';
import 'package:fonnx/models/minilml6v2/mini_lm_l6_v2.dart';
import 'package:js/js.dart';
import 'package:js/js_util.dart';
import 'package:ml_linalg/linalg.dart';

MiniLmL6V2 getMiniLmL6V2(String path) => MiniLmL6V2Web(path);

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

class MiniLmL6V2Web implements MiniLmL6V2 {
  final String modelPath;

  MiniLmL6V2Web(this.modelPath);

  @override
  Future<Vector> getEmbeddingAsVector(List<int> tokens) async {
    final jsObject = await promiseToFuture(sbertJs(modelPath, tokens));

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
