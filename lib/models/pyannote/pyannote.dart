import 'dart:typed_data';

import 'pyannote_none.dart'
    if (dart.library.io) 'pyannote_native.dart'
    if (dart.library.js) 'pyannote_web.dart';

abstract class Pyannote {
  static Pyannote? _instance;
  String get modelPath;
  String get modelName;

  static Pyannote load(String path, String modelName) {
    _instance ??= getPyannote(path, modelName);
    return _instance!;
  }

  /// Process audio data and return speaker segments
  /// 
  /// Returns a list of segments. For regular segmentation models:
  /// ```dart
  /// {
  ///   'speaker': int,    // Speaker index
  ///   'start': double,   // Start time in seconds
  ///   'stop': double,    // End time in seconds
  /// }
  /// ```
  /// 
  /// For short_scd_bigdata model:
  /// ```dart
  /// {
  ///   'timestamp': double,  // Change point time in seconds
  /// }
  /// ```
  Future<List<Map<String, dynamic>>> process(Float32List audioData, {double? step});
}