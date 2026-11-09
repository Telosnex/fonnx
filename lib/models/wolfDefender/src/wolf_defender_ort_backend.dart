import 'dart:ffi';
import 'dart:typed_data';

import 'package:fonnx/onnx/ort_ffi_bindings.dart' hide calloc, free, malloc;
import 'package:fonnx/src/ort_session_graph.dart';

import 'wolf_defender_engine.dart';

/// Runs Wolf Defender with ORT through FFI.
final class NativeWolfDefenderOnnxBackend implements WolfDefenderOnnxBackend {
  NativeWolfDefenderOnnxBackend(String modelPath)
    : _graph = OrtSessionGraph(modelPath);

  final OrtSessionGraph _graph;
  var _closed = false;

  @override
  Future<Float32List> run(Int32List ids) async {
    if (_closed) throw StateError('Wolf Defender ONNX backend is closed');
    final shape = [1, ids.length];
    final inputs = [
      _graph.int64Tensor(Int64List.fromList(ids), shape),
      _graph.int64Tensor(
        Int64List(ids.length)..fillRange(0, ids.length, 1),
        shape,
      ),
    ];
    List<Pointer<OrtValue>> outputs = const [];
    try {
      outputs = _graph.run(
        inputNames: const ['input_ids', 'attention_mask'],
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
