import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:fonnx/fonnx.dart';
import 'package:fonnx/models/magika/magika.dart';
import 'package:fonnx/models/magika/magika_isolate.dart';

Magika getMagika(String path) => MagikaNative(path);

class MagikaNative implements Magika {
  final String modelPath;
  final MagikaIsolateManager _isolate = MagikaIsolateManager();

  MagikaNative(this.modelPath);

  Fonnx? _fonnx;

  @override
  Future<MagikaType> getType(List<int> bytes) async {
    await _isolate.start();
    final Float32List resultVector;
    if (!kIsWeb && Platform.environment['FLUTTER_TEST'] == 'true') {
      resultVector = await _isolate.sendInference(modelPath, bytes);
    } else {
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
        case TargetPlatform.iOS:
          resultVector = await _getMagikaResultVectorViaPlatformChannel(bytes);
        case TargetPlatform.linux:
        case TargetPlatform.macOS:
        case TargetPlatform.windows:
          resultVector = await _getMagikaResultVectorViaFfi(bytes);
        case TargetPlatform.fuchsia:
          throw UnimplementedError();
      }
    }
    return getTypeFromResultVector(resultVector);
  }

  Future<Float32List> _getMagikaResultVectorViaFfi(List<int> bytes) {
    return _isolate.sendInference(modelPath, bytes);
  }

  Future<Float32List> _getMagikaResultVectorViaPlatformChannel(
      List<int> bytes) async {
    final fonnx = _fonnx ??= Fonnx();
    final type = await fonnx.magika(
      modelPath: modelPath,
      bytes: extractFeaturesFromBytes(Uint8List.fromList(bytes)).all,
    );
    return type;
  }
}
