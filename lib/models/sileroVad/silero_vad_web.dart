import 'dart:typed_data';

import 'package:fonnx/models/sileroVad/silero_vad.dart';

SileroVad getSileroVad(String path) => SileroVadWeb(path);

class SileroVadWeb implements SileroVad {
  @override
  final String modelPath;

  SileroVadWeb(this.modelPath);

  @override
  Future<Float32List> doInference(Uint8List bytes) {
    throw UnimplementedError();
  }
}
