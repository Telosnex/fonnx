import 'dart:isolate';
import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:fonnx/dylib_path_overrides.dart';
import 'package:fonnx/extensions/uint8list.dart';
import 'package:fonnx/onnx/ort_ffi_bindings.dart' hide calloc, free, malloc;
import 'package:fonnx/onnx/ort.dart';

class SileroVadIsolateMessage {
  final SendPort replyPort;
  final String modelPath;
  final String? ortDylibPathOverride;
  final List<int> audioBytes;
  final Map<String, dynamic> previousState;

  SileroVadIsolateMessage({
    required this.replyPort,
    required this.modelPath,
    required this.audioBytes,
    this.ortDylibPathOverride,
    this.previousState = const {},
  });
}

void sileroVadIsolateEntryPoint(SendPort mainSendPort) {
  final receivePort = ReceivePort();
  mainSendPort.send(receivePort.sendPort);

  OrtSessionObjects? ortSessionObjects;

  receivePort.listen((dynamic message) async {
    if (message is SileroVadIsolateMessage) {
      try {
        // Set the global constant because its a different global on the
        // isolate.
        if (message.ortDylibPathOverride != null) {
          fonnxOrtDylibPathOverride = message.ortDylibPathOverride;
        }
        // Lazily create the Ort session if it's not already done.
        ortSessionObjects ??= createOrtSession(
          message.modelPath,
          includeOnnxExtensionsOps: true,
        );
        // Perform the inference here using ortSessionObjects and message.tokens, retrieve result.
        final result = await _getTranscriptFfi(
          ortSessionObjects!,
          message.audioBytes,
          message.previousState,
        );
        message.replyPort.send(result);
      } catch (e) {
        // Send the error message back to the main isolate.
        message.replyPort.send(e);
      }
    } else if (message == 'close') {
      // Handle any cleanup before closing the isolate.
      if (ortSessionObjects != null) {
        cleanupOrtSession(ortSessionObjects);
      }
      Isolate.exit();
    } else {
      debugPrint('Unknown message received in the ONNX isolate.');
      throw Exception('Unknown message received in the ONNX isolate.');
    }
  });
}

void cleanupOrtSession(OrtSessionObjects? ortSessionObjects) {
  releaseOrtSessionObjects(ortSessionObjects);
}

class SileroVadIsolateManager {
  SendPort? _sendPort;
  Isolate? _isolate;
  Future<void>? _starting;

  // Start the isolate and store its SendPort.
  Future<void> start() async {
    if (_starting != null) {
      await _starting; // Wait for the pending start to finish.
      return;
    }
    if (_isolate != null) {
      return;
    }
    // The _starting flag is set with a completer which will complete when
    // the isolate start up is fully finished (including setting the _sendPort).
    final Completer<void> completer = Completer<void>();
    _starting = completer.future;

    final receivePort = ReceivePort();
    _isolate = await Isolate.spawn(
      sileroVadIsolateEntryPoint,
      receivePort.sendPort,
      onError: receivePort.sendPort, // Handle isolate errors.
    );

    // Wait for the SendPort from the new isolate.
    final sendPort = await receivePort.first as SendPort;
    _sendPort = sendPort;

    // Mark the start process as complete.
    completer.complete();
    _starting = null;
  }

  // Send data to the isolate and get a result.
  Future<Map<String, dynamic>> sendInference(
    String modelPath,
    List<int> audioBytes,
    Map<String, dynamic> previousState, {
    String? ortDylibPathOverride,
    String? ortExtensionsDylibPathOverride,
  }) async {
    await start();
    final response = ReceivePort();
    final message = SileroVadIsolateMessage(
      replyPort: response.sendPort,
      modelPath: modelPath,
      audioBytes: audioBytes,
      ortDylibPathOverride: ortDylibPathOverride,
      previousState: previousState,
    );

    _sendPort!.send(message);

    // This will wait for a response from the isolate.
    final dynamic result = await response.first;
    if (result is Map<String, dynamic>) {
      return result;
    } else if (result is Error) {
      throw result;
    } else {
      throw Exception(
        'Unknown error occurred in the ONNX isolate. Output was runtime type: ${result.runtimeType}',
      );
    }
  }

  // Shut down the isolate.
  void stop() {
    _sendPort?.send('close');
    _sendPort = null;
    _isolate = null;
  }
}

/// Return value is a Map<String, dynamic> with keys 'output', 'hn', 'cn'.
/// 'output' is a Float32List, 'hn' and 'cn' are List<List<Float32List>>.
/// The 'hn' and 'cn' are reshaped to [2, 1, 64] from [2, 64].
/// This allows them to be passed to the next inference.
///
/// It is purposefully designed to be a primitive return value in order to avoid
/// issues with use in Isolates or via Squadron. Custom objects are
/// supported by both, but in practice, add complication and aren't worth the
/// trade-off in this case.
Future<Map<String, dynamic>> _getTranscriptFfi(
  OrtSessionObjects session,
  List<int> audioBytes,
  Map<String, dynamic> previousState,
) async {
  // Inputs:
  // - input: audio, float32[batch, sequence]
  // - sr: sample rate, int64
  // - h: LTSM hidden state, float32[2, batch, 64]
  // - c: LTSM cell state, float32[2, batch, 64]
  // Outputs:
  // - output: probability of speech, float32[batch, 1]
  // - hn: LTSM hidden state, float32[2, batch, 64]
  // - cn: LTSM cell state, float32[2, batch, 64]
  final audioData = audioBytes.toAudioFloat32List();
  final usePreviousState =
      previousState.length >= 2 &&
      previousState['hn'] is List<List<Float32List>> &&
      previousState['cn'] is List<List<Float32List>>;

  final memoryInfo = calloc<Pointer<OrtMemoryInfo>>();
  final inputValue = calloc<Pointer<OrtValue>>();
  final srValue = calloc<Pointer<OrtValue>>();
  final hValue = calloc<Pointer<OrtValue>>();
  final cValue = calloc<Pointer<OrtValue>>();

  const kInputCount = 4;
  final inputNames = calloc<Pointer<Char>>(kInputCount);
  final inputNameInput = 'input'.toNativeUtf8();
  final inputNameSr = 'sr'.toNativeUtf8();
  final inputNameH = 'h'.toNativeUtf8();
  final inputNameC = 'c'.toNativeUtf8();
  final inputValues = calloc<Pointer<OrtValue>>(kInputCount);

  const kOutputCount = 3;
  final outputNames = calloc<Pointer<Char>>(kOutputCount);
  final outputNameOutput = 'output'.toNativeUtf8();
  final outputNameHn = 'hn'.toNativeUtf8();
  final outputNameCn = 'cn'.toNativeUtf8();
  final outputValues = calloc<Pointer<OrtValue>>(kOutputCount);
  final runOptionsPtr = calloc<Pointer<OrtRunOptions>>();

  Pointer<Float>? inputTensorData;
  Pointer<Int64>? srTensorData;
  Pointer<Float>? hTensorData;
  Pointer<Float>? cTensorData;

  try {
    session.api.createCpuMemoryInfo(memoryInfo);
    inputTensorData = session.api.createFloat32Tensor2D(
      inputValue,
      memoryInfo: memoryInfo.value,
      values: [audioData],
    );
    srTensorData = session.api.createInt64Tensor(
      srValue,
      memoryInfo: memoryInfo.value,
      values: [16000],
    );
    const batchSize = 1;
    final List<List<List<double>>> h =
        usePreviousState
            ? previousState['hn']
            : List.generate(
              2,
              (_) => List.generate(batchSize, (_) => List.filled(64, 0.0)),
            );
    final List<List<List<double>>> c =
        usePreviousState ? previousState['cn'] : h;
    hTensorData = session.api.createFloat32Tensor3D(
      hValue,
      memoryInfo: memoryInfo.value,
      values: h,
    );
    cTensorData = session.api.createFloat32Tensor3D(
      cValue,
      memoryInfo: memoryInfo.value,
      values: c,
    );

    inputNames[0] = inputNameInput.cast<Char>();
    inputNames[1] = inputNameSr.cast<Char>();
    inputNames[2] = inputNameH.cast<Char>();
    inputNames[3] = inputNameC.cast<Char>();
    inputValues[0] = inputValue.value;
    inputValues[1] = srValue.value;
    inputValues[2] = hValue.value;
    inputValues[3] = cValue.value;

    outputNames[0] = outputNameOutput.cast<Char>();
    outputNames[1] = outputNameHn.cast<Char>();
    outputNames[2] = outputNameCn.cast<Char>();

    session.api.createRunOptions(runOptionsPtr);
    session.api.run(
      session: session.sessionPtr.value,
      runOptions: runOptionsPtr.value,
      inputNames: inputNames,
      inputValues: inputValues,
      inputCount: kInputCount,
      outputNames: outputNames,
      outputValues: outputValues,
      outputCount: kOutputCount,
    );

    return extractOutputs(session.api, [
      outputValues[0],
      outputValues[1],
      outputValues[2],
    ]);
  } finally {
    for (var i = 0; i < kOutputCount; i++) {
      if (outputValues[i].address != 0) {
        session.api.releaseValue(outputValues[i]);
      }
    }
    if (runOptionsPtr.value.address != 0) {
      session.api.releaseRunOptions(runOptionsPtr.value);
    }
    for (final value in [inputValue, srValue, hValue, cValue]) {
      if (value.value.address != 0) {
        session.api.releaseValue(value.value);
      }
    }
    if (memoryInfo.value.address != 0) {
      session.api.releaseMemoryInfo(memoryInfo.value);
    }

    if (inputTensorData != null) {
      calloc.free(inputTensorData);
    }
    if (srTensorData != null) {
      calloc.free(srTensorData);
    }
    if (hTensorData != null) {
      calloc.free(hTensorData);
    }
    if (cTensorData != null) {
      calloc.free(cTensorData);
    }

    malloc.free(inputNameInput);
    malloc.free(inputNameSr);
    malloc.free(inputNameH);
    malloc.free(inputNameC);
    malloc.free(outputNameOutput);
    malloc.free(outputNameHn);
    malloc.free(outputNameCn);

    calloc.free(runOptionsPtr);
    calloc.free(outputValues);
    calloc.free(outputNames);
    calloc.free(inputValues);
    calloc.free(inputNames);
    calloc.free(cValue);
    calloc.free(hValue);
    calloc.free(srValue);
    calloc.free(inputValue);
    calloc.free(memoryInfo);
  }
}

Map<String, dynamic> extractOutputs(
  OrtApi api,
  List<Pointer<OrtValue>> outputValues,
) {
  final result = <String, dynamic>{};

  for (var i = 0; i < 3; i++) {
    // Iterate through output, hn, cn
    final tensorDataPointer = calloc<Pointer<Void>>();
    final tensorTypeAndShape = calloc<Pointer<OrtTensorTypeAndShapeInfo>>();
    final tensorShapeElementCount = calloc<Size>();
    try {
      api.getTensorMutableData(outputValues[i], tensorDataPointer);
      final floatsPtr = tensorDataPointer.value.cast<Float>();

      api.getTensorTypeAndShape(outputValues[i], tensorTypeAndShape);
      api.getTensorShapeElementCount(
        tensorTypeAndShape.value,
        tensorShapeElementCount,
      );
      final floatList = floatsPtr.asTypedList(tensorShapeElementCount.value);

      // Based on the assumption of shape [2, batch size (1), 64] for hn and cn
      if (i > 0) {
        // For hn and cn
        // Reshape the flat list into [2, 1, 64] - Since the batch size is known to be 1, we simplify
        final reshaped = List.generate(
          2,
          (dim1) => List.generate(
            1,
            (dim2) => Float32List.fromList(
              floatList.sublist(
                (dim1 * 64) + (dim2 * 64),
                (dim1 * 64) + ((dim2 + 1) * 64),
              ),
            ),
          ),
        );
        result[i == 1 ? 'hn' : 'cn'] = reshaped;
      } else {
        result['output'] = Float32List.fromList(floatList);
      }
    } finally {
      if (tensorTypeAndShape.value.address != 0) {
        api.releaseTensorTypeAndShapeInfo(tensorTypeAndShape.value);
      }
      calloc.free(tensorDataPointer);
      calloc.free(tensorTypeAndShape);
      calloc.free(tensorShapeElementCount);
    }
  }

  return result;
}
