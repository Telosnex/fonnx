import 'dart:isolate';
import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:fonnx/dylib_path_overrides.dart';
import 'package:fonnx/onnx/ort_ffi_bindings.dart' hide calloc, free, malloc;
import 'package:fonnx/onnx/ort.dart';

class OnnxIsolateMessage {
  final SendPort replyPort;
  final String modelPath;
  final String? ortDylibPathOverride;
  final List<int> tokens;

  OnnxIsolateMessage({
    required this.replyPort,
    required this.modelPath,
    required this.tokens,
    this.ortDylibPathOverride,
  });
}

void cleanupOrtSession(OrtSessionObjects? ortSessionObjects) {
  releaseOrtSessionObjects(ortSessionObjects);
}

enum OnnxIsolateType { miniLm, minishLab }

class OnnxIsolateManager {
  SendPort? _sendPort;
  Isolate? _isolate;
  Future<void>? _starting;

  // Start the isolate and store its SendPort.
  Future<void> start(OnnxIsolateType type) async {
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
      switch (type) {
        OnnxIsolateType.miniLm => ortMiniLmIsolateEntryPoint,
        OnnxIsolateType.minishLab => ortMinishLabIsolateEntryPoint,
      },
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
  Future<Float32List> sendInference(
    String modelPath,
    List<int> tokens, {
    String? ortDylibPathOverride,
  }) async {
    final response = ReceivePort();
    final message = OnnxIsolateMessage(
      replyPort: response.sendPort,
      modelPath: modelPath,
      tokens: tokens,
      ortDylibPathOverride: ortDylibPathOverride,
    );

    _sendPort!.send(message);

    // This will wait for a response from the isolate.
    final dynamic result = await response.first;
    if (result is Float32List) {
      return result;
    } else if (result is Error) {
      throw result;
    } else {
      throw Exception(
        'Unknown error occurred in the ONNX isolate. Result: $result',
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

void ortMiniLmIsolateEntryPoint(SendPort mainSendPort) {
  final receivePort = ReceivePort();
  mainSendPort.send(receivePort.sendPort);

  OrtSessionObjects? ortSessionObjects;

  receivePort.listen((dynamic message) async {
    if (message is OnnxIsolateMessage) {
      try {
        // Set the global constant because its a different global on the
        // isolate.
        if (message.ortDylibPathOverride != null) {
          fonnxOrtDylibPathOverride = message.ortDylibPathOverride;
        }
        // Lazily create the Ort session if it's not already done.
        ortSessionObjects ??= createOrtSession(message.modelPath);
        // Perform the inference here using ortSessionObjects and message.tokens, retrieve result.
        final result = await _getMiniLmEmbeddingFfi(
          ortSessionObjects!,
          message.tokens,
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

Future<Float32List> _getMiniLmEmbeddingFfi(
  OrtSessionObjects session,
  List<int> tokens,
) async {
  final memoryInfo = calloc<Pointer<OrtMemoryInfo>>();
  final inputIdsValue = calloc<Pointer<OrtValue>>();
  final inputMaskValue = calloc<Pointer<OrtValue>>();
  final tokenTypeValue = calloc<Pointer<OrtValue>>();
  final inputNames = calloc<Pointer<Char>>(3);
  final inputIdName = 'input_ids'.toNativeUtf8();
  final tokenTypeName = 'token_type_ids'.toNativeUtf8();
  final attentionMaskName = 'attention_mask'.toNativeUtf8();
  final inputValues = calloc<Pointer<OrtValue>>(3);
  final outputNames = calloc<Pointer<Char>>(1);
  final embeddingsName = 'embeddings'.toNativeUtf8();
  final outputValues = calloc<Pointer<OrtValue>>(1);
  final runOptionsPtr = calloc<Pointer<OrtRunOptions>>();
  final outputTensorDataPointer = calloc<Pointer<Void>>();
  final tensorTypeAndShape = calloc<Pointer<OrtTensorTypeAndShapeInfo>>();
  final tensorShapeElementCount = calloc<Size>();

  Pointer<Int64>? inputIdsTensorData;
  Pointer<Int64>? inputMaskTensorData;
  Pointer<Int64>? tokenTypeTensorData;

  try {
    session.api.createCpuMemoryInfo(memoryInfo);
    inputIdsTensorData = session.api.createInt64Tensor(
      inputIdsValue,
      memoryInfo: memoryInfo.value,
      values: tokens,
    );
    inputMaskTensorData = session.api.createInt64Tensor(
      inputMaskValue,
      memoryInfo: memoryInfo.value,
      values: List.generate(tokens.length, (index) => 1, growable: false),
    );
    tokenTypeTensorData = session.api.createInt64Tensor(
      tokenTypeValue,
      memoryInfo: memoryInfo.value,
      values: List.generate(tokens.length, (index) => 0, growable: false),
    );

    inputNames[0] = inputIdName.cast<Char>();
    inputNames[1] = tokenTypeName.cast<Char>();
    inputNames[2] = attentionMaskName.cast<Char>();
    inputValues[0] = inputIdsValue.value;
    inputValues[1] = tokenTypeValue.value;
    inputValues[2] = inputMaskValue.value;
    outputNames[0] = embeddingsName.cast<Char>();

    session.api.createRunOptions(runOptionsPtr);
    session.api.run(
      session: session.sessionPtr.value,
      runOptions: runOptionsPtr.value,
      inputNames: inputNames,
      inputValues: inputValues,
      inputCount: 3,
      outputNames: outputNames,
      outputCount: 1,
      outputValues: outputValues,
    );

    session.api.getTensorMutableData(
      outputValues.value,
      outputTensorDataPointer,
    );
    final floats = outputTensorDataPointer.value.cast<Float>();
    session.api.getTensorTypeAndShape(outputValues.value, tensorTypeAndShape);
    session.api.getTensorShapeElementCount(
      tensorTypeAndShape.value,
      tensorShapeElementCount,
    );
    return Float32List.fromList(
      floats.asTypedList(tensorShapeElementCount.value),
    );
  } finally {
    if (tensorTypeAndShape.value.address != 0) {
      session.api.releaseTensorTypeAndShapeInfo(tensorTypeAndShape.value);
    }
    if (outputValues.value.address != 0) {
      session.api.releaseValue(outputValues.value);
    }
    if (runOptionsPtr.value.address != 0) {
      session.api.releaseRunOptions(runOptionsPtr.value);
    }
    for (final value in [inputIdsValue, inputMaskValue, tokenTypeValue]) {
      if (value.value.address != 0) {
        session.api.releaseValue(value.value);
      }
    }
    if (memoryInfo.value.address != 0) {
      session.api.releaseMemoryInfo(memoryInfo.value);
    }
    if (inputIdsTensorData != null) {
      calloc.free(inputIdsTensorData);
    }
    if (inputMaskTensorData != null) {
      calloc.free(inputMaskTensorData);
    }
    if (tokenTypeTensorData != null) {
      calloc.free(tokenTypeTensorData);
    }
    malloc.free(inputIdName);
    malloc.free(tokenTypeName);
    malloc.free(attentionMaskName);
    malloc.free(embeddingsName);
    calloc.free(tensorShapeElementCount);
    calloc.free(tensorTypeAndShape);
    calloc.free(outputTensorDataPointer);
    calloc.free(runOptionsPtr);
    calloc.free(outputValues);
    calloc.free(outputNames);
    calloc.free(inputValues);
    calloc.free(inputNames);
    calloc.free(tokenTypeValue);
    calloc.free(inputMaskValue);
    calloc.free(inputIdsValue);
    calloc.free(memoryInfo);
  }
}

void ortMinishLabIsolateEntryPoint(SendPort mainSendPort) {
  final receivePort = ReceivePort();
  mainSendPort.send(receivePort.sendPort);

  OrtSessionObjects? ortSessionObjects;

  receivePort.listen((dynamic message) async {
    if (message is OnnxIsolateMessage) {
      try {
        // Set the global constant because its a different global on the
        // isolate.
        if (message.ortDylibPathOverride != null) {
          fonnxOrtDylibPathOverride = message.ortDylibPathOverride;
        }
        // Lazily create the Ort session if it's not already done.
        ortSessionObjects ??= createOrtSession(message.modelPath);
        // Perform the inference here using ortSessionObjects and message.tokens, retrieve result.
        final result = await _getMinishLabEmbeddingFfi(
          ortSessionObjects!,
          message.tokens,
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
      debugPrint(
        'Unknown message received in the ONNX isolate. Message: $message',
      );
      throw Exception(
        'Unknown message received in the ONNX isolate. Message: $message',
      );
    }
  });
}

Future<Float32List> _getMinishLabEmbeddingFfi(
  OrtSessionObjects session,
  List<int> tokens,
) async {
  final memoryInfo = calloc<Pointer<OrtMemoryInfo>>();
  final inputIdsValue = calloc<Pointer<OrtValue>>();
  final inputMaskValue = calloc<Pointer<OrtValue>>();
  final tokenTypeValue = calloc<Pointer<OrtValue>>();
  final inputNames = calloc<Pointer<Char>>(2);
  final inputIdName = 'input_ids'.toNativeUtf8();
  final tokenTypeName = 'offsets'.toNativeUtf8();
  final inputValues = calloc<Pointer<OrtValue>>(2);
  final outputNames = calloc<Pointer<Char>>(1);
  final embeddingsName = 'embeddings'.toNativeUtf8();
  final outputValues = calloc<Pointer<OrtValue>>(1);
  final runOptionsPtr = calloc<Pointer<OrtRunOptions>>();
  final outputTensorDataPointer = calloc<Pointer<Void>>();
  final tensorTypeAndShape = calloc<Pointer<OrtTensorTypeAndShapeInfo>>();
  final tensorShapeElementCount = calloc<Size>();

  Pointer<Int64>? inputIdsTensorData;
  Pointer<Int64>? inputMaskTensorData;
  Pointer<Int64>? tokenTypeTensorData;

  try {
    session.api.createCpuMemoryInfo(memoryInfo);
    inputIdsTensorData = session.api.createInt64Tensor(
      inputIdsValue,
      memoryInfo: memoryInfo.value,
      values: tokens,
      shape: [tokens.length],
    );
    final attentionMaskValues = List.generate(
      tokens.length,
      (index) => 1,
      growable: false,
    );
    inputMaskTensorData = session.api.createInt64Tensor(
      inputMaskValue,
      memoryInfo: memoryInfo.value,
      values: attentionMaskValues,
      shape: [attentionMaskValues.length],
    );
    tokenTypeTensorData = session.api.createInt64Tensor(
      tokenTypeValue,
      memoryInfo: memoryInfo.value,
      values: List.generate(1, (index) => 0, growable: false),
      shape: [1],
    );

    inputNames[0] = inputIdName.cast<Char>();
    inputNames[1] = tokenTypeName.cast<Char>();
    inputValues[0] = inputIdsValue.value;
    inputValues[1] = tokenTypeValue.value;
    outputNames[0] = embeddingsName.cast<Char>();

    session.api.createRunOptions(runOptionsPtr);
    session.api.run(
      session: session.sessionPtr.value,
      runOptions: runOptionsPtr.value,
      inputNames: inputNames,
      inputValues: inputValues,
      inputCount: 2,
      outputNames: outputNames,
      outputCount: 1,
      outputValues: outputValues,
    );

    session.api.getTensorMutableData(
      outputValues.value,
      outputTensorDataPointer,
    );
    final floats = outputTensorDataPointer.value.cast<Float>();
    session.api.getTensorTypeAndShape(outputValues.value, tensorTypeAndShape);
    session.api.getTensorShapeElementCount(
      tensorTypeAndShape.value,
      tensorShapeElementCount,
    );
    return Float32List.fromList(
      floats.asTypedList(tensorShapeElementCount.value),
    );
  } finally {
    if (tensorTypeAndShape.value.address != 0) {
      session.api.releaseTensorTypeAndShapeInfo(tensorTypeAndShape.value);
    }
    if (outputValues.value.address != 0) {
      session.api.releaseValue(outputValues.value);
    }
    if (runOptionsPtr.value.address != 0) {
      session.api.releaseRunOptions(runOptionsPtr.value);
    }
    for (final value in [inputIdsValue, inputMaskValue, tokenTypeValue]) {
      if (value.value.address != 0) {
        session.api.releaseValue(value.value);
      }
    }
    if (memoryInfo.value.address != 0) {
      session.api.releaseMemoryInfo(memoryInfo.value);
    }
    if (inputIdsTensorData != null) {
      calloc.free(inputIdsTensorData);
    }
    if (inputMaskTensorData != null) {
      calloc.free(inputMaskTensorData);
    }
    if (tokenTypeTensorData != null) {
      calloc.free(tokenTypeTensorData);
    }
    malloc.free(inputIdName);
    malloc.free(tokenTypeName);
    malloc.free(embeddingsName);
    calloc.free(tensorShapeElementCount);
    calloc.free(tensorTypeAndShape);
    calloc.free(outputTensorDataPointer);
    calloc.free(runOptionsPtr);
    calloc.free(outputValues);
    calloc.free(outputNames);
    calloc.free(inputValues);
    calloc.free(inputNames);
    calloc.free(tokenTypeValue);
    calloc.free(inputMaskValue);
    calloc.free(inputIdsValue);
    calloc.free(memoryInfo);
  }
}
