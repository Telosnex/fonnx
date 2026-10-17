import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:fonnx/onnx/ort.dart';
import 'package:fonnx/onnx/ort_ffi_bindings.dart' hide calloc, malloc, free;

import 'kokoro_stages.dart';

export 'kokoro_stages.dart' show KokoroProsody, KokoroTensor;

/// Copies outputs out of ORT before releasing any native input/output storage.
Map<String, KokoroTensor> _run(
  OrtSessionObjects session,
  Map<String, (List<int>, Object)> inputs,
  List<String> outputs,
) {
  final arena = Arena();
  final api = session.api;
  final memory = arena<Pointer<OrtMemoryInfo>>();
  final options = arena<Pointer<OrtRunOptions>>();
  final values = arena<Pointer<OrtValue>>(inputs.length);
  final result = arena<Pointer<OrtValue>>(outputs.length);
  final names = arena<Pointer<Char>>(inputs.length);
  final outNames = arena<Pointer<Char>>(outputs.length);
  try {
    api.createCpuMemoryInfo(memory);
    var index = 0;
    for (final entry in inputs.entries) {
      final (shape, data) = entry.value;
      final dims = arena<Int64>(shape.length);
      for (var i = 0; i < shape.length; i++) {
        dims[i] = shape[i];
      }
      final Pointer<Void> pointer;
      final int bytes, type, length;
      if (data is Float32List) {
        final native = arena<Float>(data.length);
        native.asTypedList(data.length).setAll(0, data);
        pointer = native.cast();
        bytes = data.length * 4;
        type = 1;
        length = data.length;
      } else {
        final ids = data as List<int>;
        final native = arena<Int64>(ids.length);
        for (var i = 0; i < ids.length; i++) {
          native[i] = ids[i];
        }
        pointer = native.cast();
        bytes = ids.length * 8;
        type = 7;
        length = ids.length;
      }
      if (shape.fold(1, (a, b) => a * b) != length) {
        throw ArgumentError('Tensor shape mismatch');
      }
      final status = api.createTensorWithDataAsOrtValue(
        values + index,
        memoryInfo: memory.value,
        inputData: pointer,
        inputDataLengthInBytes: bytes,
        inputShape: dims,
        inputShapeLengthInBytes: shape.length,
        onnxTensorElementDataType: type,
      );
      if (status.isError) throw StateError(api.consumeErrorMessage(status));
      names[index++] = entry.key.toNativeUtf8(allocator: arena).cast();
    }
    for (var i = 0; i < outputs.length; i++) {
      outNames[i] = outputs[i].toNativeUtf8(allocator: arena).cast();
    }
    api.createRunOptions(options);
    api.run(
      session: session.sessionPtr.value,
      runOptions: options.value,
      inputNames: names,
      inputValues: values,
      inputCount: inputs.length,
      outputNames: outNames,
      outputValues: result,
      outputCount: outputs.length,
    );
    final copied = <String, KokoroTensor>{};
    for (var i = 0; i < outputs.length; i++) {
      final info = arena<Pointer<OrtTensorTypeAndShapeInfo>>();
      try {
        api.getTensorTypeAndShape(result[i], info);
        final rank = arena<Size>();
        api.getDimensionsCount(info.value, rank);
        final dims = arena<Int64>(rank.value);
        final status =
            api.GetDimensions.asFunction<
              Pointer<OrtStatus> Function(
                Pointer<OrtTensorTypeAndShapeInfo>,
                Pointer<Int64>,
                int,
              )
            >()(info.value, dims, rank.value);
        if (status.isError) throw StateError(api.consumeErrorMessage(status));
        final shape = [for (var d = 0; d < rank.value; d++) dims[d]];
        final count = arena<Size>();
        api.getTensorShapeElementCount(info.value, count);
        final type = arena<UnsignedInt>();
        api.getTensorElementType(info.value, type);
        if (type.value != 1) throw StateError('Expected float32 output');
        final data = arena<Pointer<Void>>();
        api.getTensorMutableData(result[i], data);
        copied[outputs[i]] = KokoroTensor(
          Float32List.fromList(
            data.value.cast<Float>().asTypedList(count.value),
          ),
          shape,
        );
      } finally {
        if (info.value != nullptr) {
          api.releaseTensorTypeAndShapeInfo(info.value);
        }
      }
    }
    return copied;
  } finally {
    for (var i = 0; i < outputs.length; i++) {
      if (result[i] != nullptr) api.releaseValue(result[i]);
    }
    for (var i = 0; i < inputs.length; i++) {
      if (values[i] != nullptr) api.releaseValue(values[i]);
    }
    if (options.value != nullptr) api.releaseRunOptions(options.value);
    if (memory.value != nullptr) api.releaseMemoryInfo(memory.value);
    arena.releaseAll();
  }
}

KokoroProsody runKokoroProsody(
  OrtSessionObjects session, {
  required List<int> ids,
  required Float32List style,
  double speed = 1,
}) {
  kokoroCheckProsodyRequest(ids, speed);
  final result = _run(
    session,
    {
      'input_ids': ([1, ids.length + 2], <int>[0, ...ids, 0]),
      'style': ([1, 256], style),
      'speed': ([1], Float32List.fromList([speed])),
    },
    ['asr', 'f0', 'n'],
  );
  return KokoroProsody(result['asr']!, result['f0']!, result['n']!);
}

Float32List runKokoroDecoder(
  OrtSessionObjects session,
  KokoroProsody prosody,
  Float32List style,
  int first,
  int last,
) {
  final inputs = kokoroDecoderInputs(prosody, first, last);
  final count = last - first;
  final result = _run(
    session,
    {
      'asr': ([1, 512, count], inputs.asr),
      'f0': ([1, 2 * count], inputs.f0),
      'n': ([1, 2 * count], inputs.energy),
      'style': ([1, 256], style),
    },
    ['waveform'],
  )['waveform']!.data;
  if (result.length != count * 600) {
    throw StateError('Decoder returned an unexpected sample count');
  }
  return result;
}
