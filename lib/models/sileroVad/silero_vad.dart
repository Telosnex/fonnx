import 'dart:typed_data';

import 'silero_vad_none.dart'
    if (dart.library.io) 'silero_vad_native.dart'
    if (dart.library.js_interop) 'silero_vad_web.dart';

abstract class SileroVad {
  static SileroVad? _instance;
  String get modelPath;

  static SileroVad load(String path) {
    _instance ??= getSileroVad(path);
    return _instance!;
  }

  /// Runs official Silero VAD v6.2.1 on 16-kHz mono PCM16 audio.
  ///
  /// The returned map contains three `Float32List` values:
  ///
  /// * `output`: one speech probability per 512-sample (32 ms) frame;
  /// * `state`: the recurrent `[2, 1, 128]` state, flattened;
  /// * `context`: the final 64 input samples.
  ///
  /// Pass the returned map as [previousState] to continue a stream. For exact
  /// streaming behavior, non-final calls should contain a multiple of 512
  /// samples; a final partial frame is zero-padded.
  Future<Map<String, dynamic>> doInference(
    Uint8List bytes, {
    Map<String, dynamic> previousState = const {},
  });
}
