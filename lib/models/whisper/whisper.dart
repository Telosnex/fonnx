import 'dart:typed_data';

import 'whisper_none.dart'
    if (dart.library.io) 'whisper_native.dart'
    if (dart.library.js) 'whisper_web.dart';

abstract class Whisper {
  static Whisper? _instance;
  String get modelPath;

  static Whisper load(String path) {
    _instance ??= getWhisper(path);
    return _instance!;
  }

  Future<String> doInference(Uint8List bytes);

  /// Strips Whispers timestamps from the input string.
  ///
  /// Even when timestamps are disabled, the model seems to occasionally
  /// include them in the output. This method removes them.
  static String removeTimestamps(String input) {
    // Pattern to match "<|...|>"
    final pattern = RegExp(r'<\|.*?\|>');

    // Replace all instances of the pattern with an empty string
    return input.replaceAll(pattern, '').trim();
  }
}
