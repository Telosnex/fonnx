import 'dart:typed_data';

import 'package:fonnx/dylib_path_overrides.dart';
import 'package:fonnx/models/sileroVad/silero_vad.dart';
import 'package:fonnx/models/sileroVad/silero_vad_isolate.dart';

SileroVad getSileroVad(String path) => SileroVadNative(path);

class SileroVadNative implements SileroVad {
  SileroVadNative(this.modelPath);

  final SileroVadIsolateManager _sileroVadIsolateManager =
      SileroVadIsolateManager();

  @override
  final String modelPath;

  @override
  Future<Map<String, dynamic>> doInference(
    Uint8List bytes, {
    Map<String, dynamic> previousState = const {},
  }) async {
    final bytesSnapshot = Uint8List.fromList(bytes);
    final stateSnapshot = <String, dynamic>{
      for (final entry in previousState.entries)
        entry.key: switch (entry.value) {
          Float32List value => Float32List.fromList(value),
          Int64List value => Int64List.fromList(value),
          Uint8List value => Uint8List.fromList(value),
          List<dynamic> value => List<dynamic>.of(value),
          final value => value,
        },
    };
    await _sileroVadIsolateManager.start();
    return _sileroVadIsolateManager.sendInference(
      modelPath,
      bytesSnapshot,
      stateSnapshot,
      ortDylibPathOverride: fonnxOrtDylibPathOverride,
    );
  }
}
