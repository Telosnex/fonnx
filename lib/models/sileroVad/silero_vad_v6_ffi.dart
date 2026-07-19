import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:fonnx/extensions/uint8list.dart';
import 'package:fonnx/onnx/ort.dart';
import 'package:fonnx/onnx/ort_ffi_bindings.dart' hide calloc, free, malloc;

const sileroVadV6SampleRate = 16000;
const sileroVadV6ChunkSamples = 512;
const sileroVadV6ContextSamples = 64;
const sileroVadV6StateSize = 256;

/// Runs official Silero VAD v6 at 16 kHz.
///
/// The upstream ONNX wrapper prepends the previous 64 audio samples to each
/// 512-sample frame and carries a [2, 1, 128] recurrent state. This function
/// mirrors that contract while accepting one or more PCM16 frames.
Future<Map<String, dynamic>> runSileroVadV6Ffi(
  OrtSessionObjects session,
  List<int> audioBytes,
  Map<String, dynamic> previousState,
) async {
  if (audioBytes.isEmpty || audioBytes.length.isOdd) {
    throw ArgumentError.value(
      audioBytes.length,
      'audioBytes.length',
      'Must contain a non-empty, even number of PCM16 bytes',
    );
  }

  final audio = audioBytes.toAudioFloat32List();
  var state = _asFloat32List(previousState['state'], sileroVadV6StateSize);
  var context = _asFloat32List(
    previousState['context'],
    sileroVadV6ContextSamples,
  );
  final probabilities = <double>[];

  for (
    var offset = 0;
    offset < audio.length;
    offset += sileroVadV6ChunkSamples
  ) {
    final remaining = audio.length - offset;
    final count =
        remaining < sileroVadV6ChunkSamples
            ? remaining
            : sileroVadV6ChunkSamples;
    final chunk = Float32List(sileroVadV6ChunkSamples);
    chunk.setRange(0, count, audio, offset);
    final input =
        Float32List(sileroVadV6ContextSamples + sileroVadV6ChunkSamples)
          ..setRange(0, sileroVadV6ContextSamples, context)
          ..setRange(sileroVadV6ContextSamples, 576, chunk);

    final result = _runFrame(session, input, state);
    probabilities.add(result.probability);
    state = result.state;
    context = Float32List.sublistView(
      chunk,
      sileroVadV6ChunkSamples - sileroVadV6ContextSamples,
    );
  }

  return <String, dynamic>{
    'output': Float32List.fromList(probabilities),
    'state': state,
    'context': Float32List.fromList(context),
  };
}

Float32List _asFloat32List(Object? value, int length) {
  if (value is Float32List && value.length == length) {
    return Float32List.fromList(value);
  }
  if (value is List && value.length == length) {
    return Float32List.fromList(
      value.map((item) => (item as num).toDouble()).toList(),
    );
  }
  return Float32List(length);
}

_SileroVadV6FrameResult _runFrame(
  OrtSessionObjects session,
  Float32List input,
  Float32List state,
) {
  final memoryInfo = calloc<Pointer<OrtMemoryInfo>>();
  final inputValue = calloc<Pointer<OrtValue>>();
  final stateValue = calloc<Pointer<OrtValue>>();
  final sampleRateValue = calloc<Pointer<OrtValue>>();
  final inputValues = calloc<Pointer<OrtValue>>(3);
  final inputNames = calloc<Pointer<Char>>(3);
  final outputValues = calloc<Pointer<OrtValue>>(2);
  final outputNames = calloc<Pointer<Char>>(2);
  final runOptions = calloc<Pointer<OrtRunOptions>>();

  final inputName = 'input'.toNativeUtf8();
  final stateName = 'state'.toNativeUtf8();
  final sampleRateName = 'sr'.toNativeUtf8();
  final outputName = 'output'.toNativeUtf8();
  final stateOutputName = 'stateN'.toNativeUtf8();

  Pointer<Float>? inputData;
  Pointer<Float>? stateData;
  Pointer<Int64>? sampleRateData;

  try {
    session.api.createCpuMemoryInfo(memoryInfo);
    inputData = session.api.createFloat32Tensor2D(
      inputValue,
      memoryInfo: memoryInfo.value,
      values: <List<double>>[input],
    );
    stateData = session.api.createFloat32Tensor3D(
      stateValue,
      memoryInfo: memoryInfo.value,
      values: <List<List<double>>>[
        <List<double>>[state.sublist(0, 128)],
        <List<double>>[state.sublist(128, 256)],
      ],
    );
    sampleRateData = session.api.createInt64Tensor(
      sampleRateValue,
      memoryInfo: memoryInfo.value,
      values: const <int>[sileroVadV6SampleRate],
      shape: const <int>[1],
    );

    inputNames[0] = inputName.cast<Char>();
    inputNames[1] = stateName.cast<Char>();
    inputNames[2] = sampleRateName.cast<Char>();
    inputValues[0] = inputValue.value;
    inputValues[1] = stateValue.value;
    inputValues[2] = sampleRateValue.value;
    outputNames[0] = outputName.cast<Char>();
    outputNames[1] = stateOutputName.cast<Char>();

    session.api.createRunOptions(runOptions);
    session.api.run(
      session: session.sessionPtr.value,
      runOptions: runOptions.value,
      inputNames: inputNames,
      inputValues: inputValues,
      inputCount: 3,
      outputNames: outputNames,
      outputValues: outputValues,
      outputCount: 2,
    );

    final probability = _readFloats(session.api, outputValues[0]).single;
    final nextState = _readFloats(session.api, outputValues[1]);
    if (nextState.length != sileroVadV6StateSize) {
      throw StateError(
        'Silero v6 returned ${nextState.length} state values; expected '
        '$sileroVadV6StateSize',
      );
    }
    return _SileroVadV6FrameResult(probability, nextState);
  } finally {
    for (var i = 0; i < 2; i++) {
      if (outputValues[i].address != 0) {
        session.api.releaseValue(outputValues[i]);
      }
    }
    if (runOptions.value.address != 0) {
      session.api.releaseRunOptions(runOptions.value);
    }
    for (final value in <Pointer<Pointer<OrtValue>>>[
      inputValue,
      stateValue,
      sampleRateValue,
    ]) {
      if (value.value.address != 0) session.api.releaseValue(value.value);
    }
    if (memoryInfo.value.address != 0) {
      session.api.releaseMemoryInfo(memoryInfo.value);
    }

    if (inputData != null) calloc.free(inputData);
    if (stateData != null) calloc.free(stateData);
    if (sampleRateData != null) calloc.free(sampleRateData);
    malloc.free(inputName);
    malloc.free(stateName);
    malloc.free(sampleRateName);
    malloc.free(outputName);
    malloc.free(stateOutputName);
    calloc.free(runOptions);
    calloc.free(outputNames);
    calloc.free(outputValues);
    calloc.free(inputNames);
    calloc.free(inputValues);
    calloc.free(sampleRateValue);
    calloc.free(stateValue);
    calloc.free(inputValue);
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

final class _SileroVadV6FrameResult {
  const _SileroVadV6FrameResult(this.probability, this.state);

  final double probability;
  final Float32List state;
}
