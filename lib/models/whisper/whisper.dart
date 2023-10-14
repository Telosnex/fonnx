import 'dart:typed_data';

import 'whisper_none.dart'
    if (dart.library.io) 'whisper_native.dart'
    if (dart.library.js) 'whisper_web.dart';

abstract class Whisper {
  static Whisper? _instance;

  static Whisper load(String path) {
    _instance ??= getWhisper(path);
    return _instance!;
  }

  Future<String> doInference(Uint8List bytes);
}
