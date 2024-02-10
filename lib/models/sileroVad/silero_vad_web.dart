import 'dart:typed_data';

import 'package:fonnx/models/sileroVad/silero_vad.dart';

SileroVad getSileroVad(String path) => SileroVadWeb(path);

class SileroVadWeb implements SileroVad {
  @override
  final String modelPath;

  SileroVadWeb(this.modelPath);

  @override
  Future<Map<String, dynamic>> doInference(Uint8List bytes,
      {Map<String, dynamic> previousState = const {}}) {
    throw UnimplementedError();
  }
}
