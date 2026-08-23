import 'dart:typed_data';

import 'package:fonnx/models/magika/magika.dart';
import 'package:fonnx/models/magika/magika_isolate.dart';

Magika getMagika(String path) => MagikaNative(path);

class MagikaNative implements Magika {
  MagikaNative(this.modelPath);

  @override
  final String modelPath;
  final MagikaIsolateManager _isolate = MagikaIsolateManager();

  @override
  Future<MagikaType> getType(List<int> bytes) async {
    final features = extractFeaturesFromBytes(Uint8List.fromList(bytes)).all;
    await _isolate.start();
    final resultVector = await _isolate.sendInference(modelPath, features);
    return getTypeFromResultVector(resultVector);
  }
}
