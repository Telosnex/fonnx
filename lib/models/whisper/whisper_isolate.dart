import 'dart:isolate';
import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:fonnx/dylib_path_overrides.dart';
import 'package:fonnx/extensions/uint8list.dart';
import 'package:fonnx/onnx/ort_ffi_bindings.dart' hide calloc, free, malloc;
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
        ortSessionObjects ??= createOrtSession(
          message.modelPath,
          includeOnnxExtensionsOps: true,
        );
        // Perform the inference here using ortSessionObjects and message.tokens, retrieve result.
        final result = await _getTranscriptFfi(
          ortSessionObjects!,
          message.audioBytes,
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
    _sendPort = null;
    _isolate = null;
  }
}

Future<String> _getTranscriptFfi(
  OrtSessionObjects session,
  List<int> audioBytes,
) async {
  final objects = session;
  final memoryInfo = calloc<Pointer<OrtMemoryInfo>>();
  final audioStreamValue = calloc<Pointer<OrtValue>>();
  final maxLengthValue = calloc<Pointer<OrtValue>>();
  final minLengthValue = calloc<Pointer<OrtValue>>();
  final numBeamsValue = calloc<Pointer<OrtValue>>();
  final numReturnSequencesValue = calloc<Pointer<OrtValue>>();
  final lengthPenaltyValue = calloc<Pointer<OrtValue>>();
  final repetitionPenaltyValue = calloc<Pointer<OrtValue>>();
  final logitsProcessorValue = calloc<Pointer<OrtValue>>();

  const kInputCount = 8;
  final inputNames = calloc<Pointer<Char>>(kInputCount);
  final audioPcmName = 'audio_pcm'.toNativeUtf8();
  final maxLengthName = 'max_length'.toNativeUtf8();
  final minLengthName = 'min_length'.toNativeUtf8();
  final numBeamsName = 'num_beams'.toNativeUtf8();
  final numReturnSequencesName = 'num_return_sequences'.toNativeUtf8();
  final lengthPenaltyName = 'length_penalty'.toNativeUtf8();
  final repetitionPenaltyName = 'repetition_penalty'.toNativeUtf8();
  final logitsProcessorName = 'logits_processor'.toNativeUtf8();
  final inputValues = calloc<Pointer<OrtValue>>(kInputCount);

  final outputNames = calloc<Pointer<Char>>(1);
  final outputName = 'str'.toNativeUtf8();
  final outputValues = calloc<Pointer<OrtValue>>(1);
  final runOptionsPtr = calloc<Pointer<OrtRunOptions>>();
  final outputTensorDataPointer = calloc<Pointer<Void>>();
  final tensorTypeAndShape = calloc<Pointer<OrtTensorTypeAndShapeInfo>>();
  final tensorElementType = calloc<UnsignedInt>();
  final stringLengthPtr = calloc<Size>();

  Pointer<Float>? audioTensorData;
  Pointer<Int32>? maxLengthTensorData;
  Pointer<Int32>? minLengthTensorData;
  Pointer<Int32>? numBeamsTensorData;
  Pointer<Int32>? numReturnSequencesTensorData;
  Pointer<Float>? lengthPenaltyTensorData;
  Pointer<Float>? repetitionPenaltyTensorData;
  Pointer<Int32>? logitsProcessorTensorData;
  Pointer<Uint8>? stringPtr;

  try {
    objects.api.createCpuMemoryInfo(memoryInfo);
    audioTensorData = objects.api.createFloat32Tensor2D(
      audioStreamValue,
      memoryInfo: memoryInfo.value,
      values: [audioBytes.toAudioFloat32List()],
    );
    maxLengthTensorData = objects.api.createInt32Tensor(
      maxLengthValue,
      memoryInfo: memoryInfo.value,
      values: [200],
    );
    minLengthTensorData = objects.api.createInt32Tensor(
      minLengthValue,
      memoryInfo: memoryInfo.value,
      values: [0],
    );
    numBeamsTensorData = objects.api.createInt32Tensor(
      numBeamsValue,
      memoryInfo: memoryInfo.value,
      values: [2],
    );
    numReturnSequencesTensorData = objects.api.createInt32Tensor(
      numReturnSequencesValue,
      memoryInfo: memoryInfo.value,
      values: [1],
    );
    lengthPenaltyTensorData = objects.api.createFloat32Tensor(
      lengthPenaltyValue,
      memoryInfo: memoryInfo.value,
      values: [1.0],
    );
    repetitionPenaltyTensorData = objects.api.createFloat32Tensor(
      repetitionPenaltyValue,
      memoryInfo: memoryInfo.value,
      values: [1.0],
    );
    // 1 for include timestamps, 0 for not.
    logitsProcessorTensorData = objects.api.createInt32Tensor(
      logitsProcessorValue,
      memoryInfo: memoryInfo.value,
      values: [0],
    );

    inputNames[0] = audioPcmName.cast<Char>();
    inputNames[1] = maxLengthName.cast<Char>();
    inputNames[2] = minLengthName.cast<Char>();
    inputNames[3] = numBeamsName.cast<Char>();
    inputNames[4] = numReturnSequencesName.cast<Char>();
    inputNames[5] = lengthPenaltyName.cast<Char>();
    inputNames[6] = repetitionPenaltyName.cast<Char>();
    inputNames[7] = logitsProcessorName.cast<Char>();
    inputValues[0] = audioStreamValue.value;
    inputValues[1] = maxLengthValue.value;
    inputValues[2] = minLengthValue.value;
    inputValues[3] = numBeamsValue.value;
    inputValues[4] = numReturnSequencesValue.value;
    inputValues[5] = lengthPenaltyValue.value;
    inputValues[6] = repetitionPenaltyValue.value;
    inputValues[7] = logitsProcessorValue.value;

    outputNames[0] = outputName.cast<Char>();

    objects.api.createRunOptions(runOptionsPtr);
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

    objects.api.getTensorMutableData(
      outputValues.value,
      outputTensorDataPointer,
    );
    objects.api.getTensorTypeAndShape(outputValues.value, tensorTypeAndShape);
    objects.api.getTensorElementType(
      tensorTypeAndShape.value,
      tensorElementType,
    );
    assert(
      tensorElementType.value ==
          ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_STRING.value,
    );

    objects.api.getStringTensorElementLength(
      outputValues.value,
      0,
      stringLengthPtr,
    );
    final stringLength = stringLengthPtr.value;
    stringPtr = calloc<Uint8>(stringLength);
    objects.api.getStringTensorElement(
      outputValues.value,
      stringLength,
      0,
      stringPtr.cast<Void>(),
    );
    return stringPtr.cast<Utf8>().toDartString(length: stringLength);
  } catch (e, st) {
    // ignore: avoid_print
    print('Error in WhisperIsolate._getTranscriptFfi: $e');
    // ignore: avoid_print
    print(st);
    return '';
  } finally {
    if (tensorTypeAndShape.value.address != 0) {
      objects.api.releaseTensorTypeAndShapeInfo(tensorTypeAndShape.value);
    }
    if (outputValues.value.address != 0) {
      objects.api.releaseValue(outputValues.value);
    }
    if (runOptionsPtr.value.address != 0) {
      objects.api.releaseRunOptions(runOptionsPtr.value);
    }
    for (final value in [
      audioStreamValue,
      maxLengthValue,
      minLengthValue,
      numBeamsValue,
      numReturnSequencesValue,
      lengthPenaltyValue,
      repetitionPenaltyValue,
      logitsProcessorValue,
    ]) {
      if (value.value.address != 0) {
        objects.api.releaseValue(value.value);
      }
    }
    if (memoryInfo.value.address != 0) {
      objects.api.releaseMemoryInfo(memoryInfo.value);
    }

    if (audioTensorData != null) {
      calloc.free(audioTensorData);
    }
    if (maxLengthTensorData != null) {
      calloc.free(maxLengthTensorData);
    }
    if (minLengthTensorData != null) {
      calloc.free(minLengthTensorData);
    }
    if (numBeamsTensorData != null) {
      calloc.free(numBeamsTensorData);
    }
    if (numReturnSequencesTensorData != null) {
      calloc.free(numReturnSequencesTensorData);
    }
    if (lengthPenaltyTensorData != null) {
      calloc.free(lengthPenaltyTensorData);
    }
    if (repetitionPenaltyTensorData != null) {
      calloc.free(repetitionPenaltyTensorData);
    }
    if (logitsProcessorTensorData != null) {
      calloc.free(logitsProcessorTensorData);
    }
    if (stringPtr != null) {
      calloc.free(stringPtr);
    }

    malloc.free(audioPcmName);
    malloc.free(maxLengthName);
    malloc.free(minLengthName);
    malloc.free(numBeamsName);
    malloc.free(numReturnSequencesName);
    malloc.free(lengthPenaltyName);
    malloc.free(repetitionPenaltyName);
    malloc.free(logitsProcessorName);
    malloc.free(outputName);

    calloc.free(stringLengthPtr);
    calloc.free(tensorElementType);
    calloc.free(tensorTypeAndShape);
    calloc.free(outputTensorDataPointer);
    calloc.free(runOptionsPtr);
    calloc.free(outputValues);
    calloc.free(outputNames);
    calloc.free(inputValues);
    calloc.free(inputNames);
    calloc.free(logitsProcessorValue);
    calloc.free(repetitionPenaltyValue);
    calloc.free(lengthPenaltyValue);
    calloc.free(numReturnSequencesValue);
    calloc.free(numBeamsValue);
    calloc.free(minLengthValue);
    calloc.free(maxLengthValue);
    calloc.free(audioStreamValue);
    calloc.free(memoryInfo);
  }
}
