import 'dart:typed_data';

import 'silero_vad_none.dart'
    if (dart.library.io) 'silero_vad_native.dart'
    if (dart.library.js) 'silero_vad_web.dart';

abstract class SileroVad {
  static SileroVad? _instance;
  String get modelPath;

  static SileroVad load(String path) {
    _instance ??= getSileroVad(path);
    return _instance!;
  }

  Future<Float32List> doInference(Uint8List bytes);
}
