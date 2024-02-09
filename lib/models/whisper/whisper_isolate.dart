import 'dart:isolate';
import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:fonnx/dylib_path_overrides.dart';
import 'package:fonnx/onnx/ort_ffi_bindings.dart' hide calloc, free;
import 'package:fonnx/onnx/ort.dart';

class WhisperIsolateMessage {
  final SendPort replyPort;
  final String modelPath;
  final String? ortDylibPathOverride;
  final String? ortExtensionsDylibPathOverride;
  final List<int> audioBytes;

  WhisperIsolateMessage({
    required this.replyPort,
    required this.modelPath,
    required this.audioBytes,
    this.ortDylibPathOverride,
    this.ortExtensionsDylibPathOverride,
  });
}

void whisperIsolateEntryPoint(SendPort mainSendPort) {
  final receivePort = ReceivePort();
  mainSendPort.send(receivePort.sendPort);

  OrtSessionObjects? ortSessionObjects;

  receivePort.listen((dynamic message) async {
    if (message is WhisperIsolateMessage) {
      try {
        // Set the global constant because its a different global on the
        // isolate.
        if (message.ortDylibPathOverride != null) {
          fonnxOrtDylibPathOverride = message.ortDylibPathOverride;
        }
        if (message.ortExtensionsDylibPathOverride != null) {
          fonnxOrtExtensionsDylibPathOverride =
              message.ortExtensionsDylibPathOverride;
        }
        // Lazily create the Ort session if it's not already done.
        ortSessionObjects ??=
            createOrtSession(message.modelPath, includeOnnxExtensionsOps: true);
        // Perform the inference here using ortSessionObjects and message.tokens, retrieve result.
        final result =
            await _getTranscriptFfi(ortSessionObjects!, message.audioBytes);
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
  if (ortSessionObjects == null) {
    return;
  }
  // Cleanup the Ort session? Currently we assume that the session is desired
  // for the lifetime of the application. Makes sense for embeddings models.
  // _Maybe_ Whisper. Definitely not an LLM.
}

class WhisperIsolateManager {
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
      whisperIsolateEntryPoint,
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
  Future<String> sendInference(
    String modelPath,
    List<int> audioBytes, {
    String? ortDylibPathOverride,
    String? ortExtensionsDylibPathOverride,
  }) async {
    await start();
    final response = ReceivePort();
    final message = WhisperIsolateMessage(
      replyPort: response.sendPort,
      modelPath: modelPath,
      audioBytes: audioBytes,
      ortDylibPathOverride: ortDylibPathOverride,
      ortExtensionsDylibPathOverride: ortExtensionsDylibPathOverride,
    );

    _sendPort!.send(message);

    // This will wait for a response from the isolate.
    final dynamic result = await response.first;
    if (result is String) {
      return result;
    } else if (result is Error) {
      throw result;
    } else {
      throw Exception('Unknown error occurred in the ONNX isolate.');
    }
  }

  // Shut down the isolate.
  void stop() {
    _sendPort?.send('close');
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
  }
}

Future<String> _getTranscriptFfi(
    OrtSessionObjects session, List<int> audioBytes) async {
  final sw = Stopwatch()..start();

  final objects = session;
  final memoryInfo = calloc<Pointer<OrtMemoryInfo>>();
  objects.api.createCpuMemoryInfo(memoryInfo);
  final audioStreamValue = calloc<Pointer<OrtValue>>();
  objects.api.createUint8Tensor(
    audioStreamValue,
    memoryInfo: memoryInfo.value,
    values: audioBytes,
  );
  final maxLengthValue = calloc<Pointer<OrtValue>>();
  objects.api.createInt32Tensor(
    maxLengthValue,
    memoryInfo: memoryInfo.value,
    values: [200],
  );
  final minLengthValue = calloc<Pointer<OrtValue>>();
  objects.api.createInt32Tensor(
    minLengthValue,
    memoryInfo: memoryInfo.value,
    values: [0],
  );
  final numBeamsValue = calloc<Pointer<OrtValue>>();
  objects.api.createInt32Tensor(
    numBeamsValue,
    memoryInfo: memoryInfo.value,
    values: [1],
  );
  final numReturnSequencesValue = calloc<Pointer<OrtValue>>();
  objects.api.createInt32Tensor(
    numReturnSequencesValue,
    memoryInfo: memoryInfo.value,
    values: [1],
  );
  final lengthPenaltyValue = calloc<Pointer<OrtValue>>();
  objects.api.createFloat32Tensor(
    lengthPenaltyValue,
    memoryInfo: memoryInfo.value,
    values: [1.0],
  );
  final repetitionPenaltyValue = calloc<Pointer<OrtValue>>();
  objects.api.createFloat32Tensor(
    repetitionPenaltyValue,
    memoryInfo: memoryInfo.value,
    values: [1.0],
  );
  // 1 for include timestamps, 0 for not.
  final logitsProcessorValue = calloc<Pointer<OrtValue>>();
  objects.api.createInt32Tensor(
    logitsProcessorValue,
    memoryInfo: memoryInfo.value,
    values: [0],
  );

  const kInputCount = 8;
  final inputNamesPointer = calloc<Pointer<Pointer<Char>>>(kInputCount);
  inputNamesPointer[0] = 'audio_stream'.toNativeUtf8().cast();
  inputNamesPointer[1] = 'max_length'.toNativeUtf8().cast();
  inputNamesPointer[2] = 'min_length'.toNativeUtf8().cast();
  inputNamesPointer[3] = 'num_beams'.toNativeUtf8().cast();
  inputNamesPointer[4] = 'num_return_sequences'.toNativeUtf8().cast();
  inputNamesPointer[5] = 'length_penalty'.toNativeUtf8().cast();
  inputNamesPointer[6] = 'repetition_penalty'.toNativeUtf8().cast();
  inputNamesPointer[7] = 'logits_processor'.toNativeUtf8().cast();
  final inputNames = inputNamesPointer.cast<Pointer<Char>>();
  final inputValues = calloc<Pointer<OrtValue>>(kInputCount);
  inputValues[0] = audioStreamValue.value;
  inputValues[1] = maxLengthValue.value;
  inputValues[2] = minLengthValue.value;
  inputValues[3] = numBeamsValue.value;
  inputValues[4] = numReturnSequencesValue.value;
  inputValues[5] = lengthPenaltyValue.value;
  inputValues[6] = repetitionPenaltyValue.value;
  inputValues[7] = logitsProcessorValue.value;
  final outputNamesPointer = calloc<Pointer<Char>>();
  outputNamesPointer[0] = 'str'.toNativeUtf8().cast();
  final outputNames = outputNamesPointer.cast<Pointer<Char>>();
  final outputValues = calloc<Pointer<OrtValue>>();
  final runOptionsPtr = calloc<Pointer<OrtRunOptions>>();
  objects.api.createRunOptions(runOptionsPtr);
  sw.stop();
  sw.reset();
  sw.start();
  objects.api.run(
    session: objects.sessionPtr.value,
    runOptions: runOptionsPtr.value,
    inputNames: inputNames,
    inputValues: inputValues,
    inputCount: kInputCount,
    outputNames: outputNames,
    outputCount: 1,
    outputValues: outputValues,
  );


  final outputTensorDataPointer = calloc<Pointer<Void>>();
  objects.api.getTensorMutableData(outputValues.value, outputTensorDataPointer);

  final tensorTypeAndShape = calloc<Pointer<OrtTensorTypeAndShapeInfo>>();
  objects.api.getTensorTypeAndShape(outputValues.value, tensorTypeAndShape);
  final tensorElementType = calloc<Int32>();
  objects.api.getTensorElementType(tensorTypeAndShape.value, tensorElementType);
  assert(tensorElementType.value ==
      ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_STRING);

  final stringLengthPtr = calloc<Size>();
  objects.api
      .getStringTensorElementLength(outputValues.value, 0, stringLengthPtr);
  final stringLength = stringLengthPtr.value;
  final stringPtr = calloc<Uint8>(stringLength);
  objects.api.getStringTensorElement(
      outputValues.value, stringLength, 0, stringPtr.cast<Void>());
  final string = stringPtr.cast<Utf8>().toDartString(length: stringLength);

  sw.stop();
  sw.reset();
  sw.start();
  calloc.free(memoryInfo);
  calloc.free(audioStreamValue);
  calloc.free(maxLengthValue);
  calloc.free(minLengthValue);
  calloc.free(numBeamsValue);
  calloc.free(numReturnSequencesValue);
  calloc.free(lengthPenaltyValue);
  calloc.free(repetitionPenaltyValue);
  calloc.free(logitsProcessorValue);
  calloc.free(inputNamesPointer);
  calloc.free(inputValues);
  calloc.free(outputNamesPointer);
  calloc.free(outputValues);
  calloc.free(runOptionsPtr);
  calloc.free(outputTensorDataPointer);
  return string;
}
