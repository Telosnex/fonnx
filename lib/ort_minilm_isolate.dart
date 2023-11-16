import 'dart:isolate';
import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:fonnx/onnx/ort_ffi_bindings.dart' hide calloc, free;
import 'package:fonnx/onnx/ort.dart';

class OnnxIsolateMessage {
  final SendPort replyPort;
  final String modelPath;
  final List<int> tokens;

  OnnxIsolateMessage({
    required this.replyPort,
    required this.modelPath,
    required this.tokens,
  });
}

void ortMiniLmIsolateEntryPoint(SendPort mainSendPort) {
  final receivePort = ReceivePort();
  mainSendPort.send(receivePort.sendPort);

  OrtSessionObjects? ortSessionObjects;

  receivePort.listen((dynamic message) async {
    if (message is OnnxIsolateMessage) {
      try {
        // Lazily create the Ort session if it's not already done.
        ortSessionObjects ??= createOrtSession(message.modelPath);
        // Perform the inference here using ortSessionObjects and message.tokens, retrieve result.
        final result =
            await _getEmbeddingFfi(ortSessionObjects!, message.tokens);
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

class OnnxIsolateManager {
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
      ortMiniLmIsolateEntryPoint,
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
  Future<Float32List> sendInference(String modelPath, List<int> tokens) async {
    final response = ReceivePort();
    final message = OnnxIsolateMessage(
      replyPort: response.sendPort,
      modelPath: modelPath,
      tokens: tokens,
    );

    _sendPort!.send(message);

    // This will wait for a response from the isolate.
    final dynamic result = await response.first;
    if (result is Float32List) {
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

Future<Float32List> _getEmbeddingFfi(
    OrtSessionObjects session, List<int> tokens) async {
  final memoryInfo = calloc<Pointer<OrtMemoryInfo>>();
  session.api.createCpuMemoryInfo(memoryInfo);
  final inputIdsValue = calloc<Pointer<OrtValue>>();
  session.api.createInt64Tensor(
    inputIdsValue,
    memoryInfo: memoryInfo.value,
    values: tokens,
  );
  final inputMaskValue = calloc<Pointer<OrtValue>>();
  session.api.createInt64Tensor(
    inputMaskValue,
    memoryInfo: memoryInfo.value,
    values: List.generate(tokens.length, (index) => 1, growable: false),
  );
  final tokenTypeValue = calloc<Pointer<OrtValue>>();
  session.api.createInt64Tensor(
    tokenTypeValue,
    memoryInfo: memoryInfo.value,
    values: List.generate(tokens.length, (index) => 0, growable: false),
  );
  final inputNamesPointer = calloc<Pointer<Pointer<Char>>>(3);
  inputNamesPointer[0] = 'input_ids'.toNativeUtf8().cast();
  inputNamesPointer[1] = 'token_type_ids'.toNativeUtf8().cast();
  inputNamesPointer[2] = 'attention_mask'.toNativeUtf8().cast();
  final inputNames = inputNamesPointer.cast<Pointer<Char>>();
  final inputValues = calloc<Pointer<OrtValue>>(3);
  inputValues[0] = inputIdsValue.value;
  inputValues[1] = tokenTypeValue.value;
  inputValues[2] = inputMaskValue.value;

  final outputNamesPointer = calloc<Pointer<Char>>();
  outputNamesPointer[0] = 'embeddings'.toNativeUtf8().cast();

  final outputValuesPtr = calloc<Pointer<OrtValue>>();
  final outputValues = outputValuesPtr.cast<Pointer<OrtValue>>();
  final runOptionsPtr = calloc<Pointer<OrtRunOptions>>();
  session.api.createRunOptions(runOptionsPtr);

  session.api.run(
    session: session.sessionPtr.value,
    runOptions: runOptionsPtr.value,
    inputNames: inputNames,
    inputValues: inputValues,
    inputCount: 3,
    outputNames: outputNamesPointer,
    outputCount: 1,
    outputValues: outputValues,
  );

  final outputTensorDataPointer = calloc<Pointer<Void>>();
  session.api.getTensorMutableData(outputValues.value, outputTensorDataPointer);
  final outputTensorDataPtr = outputTensorDataPointer.value;
  final floats = outputTensorDataPtr.cast<Float>();

  final tensorTypeAndShape = calloc<Pointer<OrtTensorTypeAndShapeInfo>>();
  session.api.getTensorTypeAndShape(outputValues.value, tensorTypeAndShape);
  final tensorShapeElementCount = calloc<Size>();
  session.api.getTensorShapeElementCount(
    tensorTypeAndShape.value,
    tensorShapeElementCount,
  );
  final elementCount = tensorShapeElementCount.value;
  final floatList = floats.asTypedList(elementCount);

  calloc.free(memoryInfo);
  calloc.free(inputIdsValue);
  calloc.free(inputMaskValue);
  calloc.free(tokenTypeValue);
  calloc.free(inputNamesPointer);
  calloc.free(inputValues);
  calloc.free(outputNamesPointer);
  calloc.free(outputValuesPtr);
  calloc.free(runOptionsPtr);
  calloc.free(outputTensorDataPointer);
  calloc.free(tensorTypeAndShape);
  calloc.free(tensorShapeElementCount);

  return floatList;
}
