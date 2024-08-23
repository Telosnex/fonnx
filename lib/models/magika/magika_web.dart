import 'dart:async';
import 'dart:typed_data';
import 'dart:js_interop';

import 'package:fonnx/models/magika/magika.dart';

Magika getMagika(String path) => MagikaWeb(path);

@JS('window.magikaInferenceAsyncJs')
external JSPromise<JSFloat32Array?> magikaInferenceAsyncJs(
    String modelPath, JSUint8Array fileBytes);

class MagikaWeb implements Magika {
  final String modelPath;

  MagikaWeb(this.modelPath);

  @override
  Future<MagikaType> getType(List<int> fileBytes) async {
    final features = extractFeaturesFromBytes(Uint8List.fromList(fileBytes));
    final jsFeatures = Uint8List.fromList(features.all).toJS;
    final jsPromise = magikaInferenceAsyncJs(modelPath, jsFeatures);
    final jsResult = await jsPromise.toDart;

    if (jsResult == null) {
      throw Exception('Magika result returned from JS code is null');
    }

    final dartResult = Float32List.fromList(jsResult.toDart);
    return getTypeFromResultVector(dartResult);
  }
}
