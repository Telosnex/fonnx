import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:fonnx/piper/piper_models.dart';

import 'piper_none.dart'
    if (dart.library.io) 'piper_native.dart'
    if (dart.library.js) 'piper_web.dart';

abstract class Piper {
  static Piper? _instance;

  static Piper load(String path) {
    _instance ??= getPiper(path);
    return _instance!;
  }

  static Future<PiperConfig?> loadConfig(String path) async {
    final bytes = await File(path).readAsBytes();
    final string = String.fromCharCodes(bytes.buffer.asUint8List());
    final json = jsonDecode(string);
    return PiperConfig.fromJson(json);
  }
}
