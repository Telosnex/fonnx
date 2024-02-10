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

  /// Return value is a Map<String, dynamic> with keys 'output', 'hn', 'cn'.
  /// 'output' is a Float32List, 'hn' and 'cn' are List<List<Float32List>>.
  /// The 'hn' and 'cn' are reshaped to [2, 1, 64] from [2, 64].
  /// This allows them to be passed to the next inference.
  /// 
  /// [previousState] is a Map<String, dynamic> with keys 'hn' and 'cn'.
  /// It will not be used if those keys are not present.
  Future<Map<String, dynamic>> doInference(Uint8List bytes,
      {Map<String, dynamic> previousState = const {}});
}
