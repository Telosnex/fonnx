import 'dart:typed_data';

import 'pyannote_none.dart'
    if (dart.library.io) 'pyannote_native.dart'
    if (dart.library.js) 'pyannote_web.dart';

abstract class Pyannote {
  static Pyannote? _instance;
  String get modelPath;

  static Pyannote load(String path) {
    _instance ??= getPyannote(path);
    return _instance!;
  }

 /// Converts int16 PCM bytes to normalized float32 samples
  static Float32List int16PcmBytesToFloat32(Uint8List bytes) {
  // Convert bytes to Int16 samples
  final samples = Int16List.sublistView(bytes);

  // Convert to Float32, scaling from Int16 range to [-1, 1]
  final float32Data = Float32List(samples.length);
  for (int i = 0; i < samples.length; i++) {
    float32Data[i] = samples[i] / 32768.0; // 32768 = 2^15
  }
  return float32Data;
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
  Future<List<Map<String, dynamic>>> process(Float32List audioData);
}