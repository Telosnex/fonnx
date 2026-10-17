import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:fonnx/models/kokoro/kokoro_tokens.dart';
import 'package:fonnx/onnx/ort.dart';
import 'package:fonnx/onnx/ort_ffi_bindings.dart' hide calloc, free, malloc;

export 'kokoro_tokens.dart';

/// Runs Kokoro on unpadded phoneme [ids]. Returns 24 kHz float PCM.
Float32List runKokoroFfi(
  OrtSessionObjects session, {
  required List<int> ids,
  required Float32List voice,
  double speed = 1.0,
}) {
  final style = kokoroStyleForLength(voice, ids.length);
  final paddedIds = <int>[0, ...ids, 0];

  final api = session.api;
  final memoryInfo = calloc<Pointer<OrtMemoryInfo>>();
  final idsValue = calloc<Pointer<OrtValue>>();
  final styleValue = calloc<Pointer<OrtValue>>();
  final speedValue = calloc<Pointer<OrtValue>>();
  final inputValues = calloc<Pointer<OrtValue>>(3);
  final inputNames = calloc<Pointer<Char>>(3);
  final outputValues = calloc<Pointer<OrtValue>>(1);
  final outputNames = calloc<Pointer<Char>>(1);
  final runOptions = calloc<Pointer<OrtRunOptions>>();

  final idsName = 'input_ids'.toNativeUtf8();
  final styleName = 'style'.toNativeUtf8();
  final speedName = 'speed'.toNativeUtf8();
  final waveformName = 'waveform'.toNativeUtf8();

  Pointer<Int64>? idsData;
  Pointer<Float>? styleData;
  Pointer<Float>? speedData;

  try {
    api.createCpuMemoryInfo(memoryInfo);
    idsData = api.createInt64Tensor(
      idsValue,
      memoryInfo: memoryInfo.value,
      values: paddedIds,
      shape: <int>[1, paddedIds.length],
    );
    styleData = api.createFloat32Tensor2D(
      styleValue,
      memoryInfo: memoryInfo.value,
      values: <List<double>>[style],
    );
    speedData = api.createFloat32Tensor(
      speedValue,
      memoryInfo: memoryInfo.value,
      values: <double>[speed],
    );

    inputNames[0] = idsName.cast<Char>();
    inputNames[1] = styleName.cast<Char>();
    inputNames[2] = speedName.cast<Char>();
    inputValues[0] = idsValue.value;
    inputValues[1] = styleValue.value;
    inputValues[2] = speedValue.value;
    outputNames[0] = waveformName.cast<Char>();

    api.createRunOptions(runOptions);
    api.run(
      session: session.sessionPtr.value,
      runOptions: runOptions.value,
      inputNames: inputNames,
      inputValues: inputValues,
      inputCount: 3,
      outputNames: outputNames,
      outputValues: outputValues,
      outputCount: 1,
    );
    return _readFloats(api, outputValues[0]);
  } finally {
    if (outputValues[0].address != 0) api.releaseValue(outputValues[0]);
    if (runOptions.value.address != 0) {
      api.releaseRunOptions(runOptions.value);
    }
    for (final value in <Pointer<Pointer<OrtValue>>>[
      idsValue,
      styleValue,
      speedValue,
    ]) {
      if (value.value.address != 0) api.releaseValue(value.value);
    }
    if (memoryInfo.value.address != 0) {
      api.releaseMemoryInfo(memoryInfo.value);
    }
    if (idsData != null) calloc.free(idsData);
    if (styleData != null) calloc.free(styleData);
    if (speedData != null) calloc.free(speedData);
    malloc.free(idsName);
    malloc.free(styleName);
    malloc.free(speedName);
    malloc.free(waveformName);
    calloc.free(runOptions);
    calloc.free(outputNames);
    calloc.free(outputValues);
    calloc.free(inputNames);
    calloc.free(inputValues);
    calloc.free(speedValue);
    calloc.free(styleValue);
    calloc.free(idsValue);
    calloc.free(memoryInfo);
  }
}

Float32List _readFloats(OrtApi api, Pointer<OrtValue> value) {
  final data = calloc<Pointer<Void>>();
  final shape = calloc<Pointer<OrtTensorTypeAndShapeInfo>>();
  final count = calloc<Size>();
  try {
    api.getTensorMutableData(value, data);
    api.getTensorTypeAndShape(value, shape);
    api.getTensorShapeElementCount(shape.value, count);
    return Float32List.fromList(
      data.value.cast<Float>().asTypedList(count.value),
    );
  } finally {
    if (shape.value.address != 0) {
      api.releaseTensorTypeAndShapeInfo(shape.value);
    }
    calloc.free(count);
    calloc.free(shape);
    calloc.free(data);
  }
}
