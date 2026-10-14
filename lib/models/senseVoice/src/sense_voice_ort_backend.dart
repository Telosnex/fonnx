import 'dart:ffi';
import 'dart:typed_data';

import 'package:fonnx/onnx/ort_ffi_bindings.dart' hide calloc, free, malloc;
import 'package:fonnx/src/ort_session_graph.dart';

import 'sense_voice_engine.dart';
import 'sense_voice_features.dart';

/// Runs SenseVoice with ORT through FFI.
final class NativeSenseVoiceOnnxBackend implements SenseVoiceOnnxBackend {
  NativeSenseVoiceOnnxBackend(String modelPath)
    : _graph = OrtSessionGraph(modelPath);

  final OrtSessionGraph _graph;
  var _closed = false;

  @override
  Future<Float32List> run(
    Float32List features,
    int frames,
    int language,
  ) async {
    if (_closed) throw StateError('SenseVoice ONNX backend is closed');
    final inputs = [
      _graph.floatTensor(features, [1, frames, senseVoiceFeatureWidth]),
      _graph.int32Tensor(Int32List.fromList([frames]), const [1]),
      _graph.int32Tensor(Int32List.fromList([language]), const [1]),
      _graph.int32Tensor(Int32List.fromList([senseVoiceWithItn]), const [1]),
    ];
    List<Pointer<OrtValue>> outputs = const [];
    try {
      outputs = _graph.run(
        inputNames: const ['x', 'x_length', 'language', 'text_norm'],
        inputValues: [for (final input in inputs) input.value],
        outputNames: const ['logits'],
      );
      return _graph.copyFloatTensor(outputs.single);
    } finally {
      for (final input in inputs) {
        input.release();
      }
      for (final output in outputs) {
        _graph.releaseValue(output);
      }
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _graph.close();
  }
}
