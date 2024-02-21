import 'dart:typed_data';

import 'package:fonnx/models/magika/magika.dart';
import 'package:js/js.dart';
import 'package:js/js_util.dart';

Magika getMagika(String path) => MagikaWeb(path);

@JS()
class Promise<T> {
  external Promise(
      void Function(void Function(T result) resolve, Function reject) executor);
  external Promise then(void Function(T result) onFulfilled,
      [Function onRejected]);
}

@JS('window.magikaInferenceAsyncJs')
external Promise<Float32List> magikaInferenceAsyncJs(
    String modelPath, List<int> fileBytes);

class MagikaWeb implements Magika {
  final String modelPath;

  MagikaWeb(this.modelPath);

  @override
  Future<MagikaType> getType(List<int> fileBytes) async {
    final features = extractFeaturesFromBytes(Uint8List.fromList(fileBytes));
    final jsObject =
        await promiseToFuture(magikaInferenceAsyncJs(modelPath, features.all));
    if (jsObject == null) {
      throw Exception('Magika result returned from JS code is null');
    }
    return getTypeFromResultVector(jsObject);
  }
}
