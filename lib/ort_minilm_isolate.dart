import 'dart:isolate';
import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:fonnx/dylib_path_overrides.dart';
import 'package:fonnx/onnx/ort_ffi_bindings.dart' hide calloc, free;
import 'package:fonnx/onnx/ort.dart';
import 'package:fonnx/fonnx.dart';

class OnnxIsolateMessage {
  final SendPort replyPort;
  final String modelPath;
  final String? ortDylibPathOverride;
  final List<int> tokens;
  final String? outputName; // Optional: allows client to specify output name

  OnnxIsolateMessage({
    required this.replyPort,
    required this.modelPath,
    required this.tokens,
    this.ortDylibPathOverride,
    this.outputName,
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

enum OnnxIsolateType { miniLm, minishLab }

class OnnxIsolateManager {
  SendPort? _sendPort;
  Isolate? _isolate;
  Future<void>? _starting;
  Fonnx? _fonnx; // For Android/iOS method channel usage
  OnnxIsolateType? _type; // Track the type for Android/iOS method channel selection

  // Start the isolate and store its SendPort.
  // On Android/iOS, this is a no-op since we use method channels instead.
  Future<void> start(OnnxIsolateType type) async {
    _type = type; // Store type for later use
    // On Android/iOS, use method channels instead of isolates
    if (Platform.isAndroid || Platform.isIOS) {
      _fonnx = Fonnx();
      return; // No isolate needed on these platforms
    }
    
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
  // On Android/iOS, uses method channels instead of isolates.
  Future<Float32List> sendInference(
    String modelPath,
    List<int> tokens, {
    String? ortDylibPathOverride,
    String? outputName, // Optional: specify model output name (e.g., 'embeddings', 'sentence_embedding', 'last_hidden_state')
  }) async {
    // On Android/iOS, use method channels instead of isolates
    if (Platform.isAndroid || Platform.isIOS) {
      // Ensure Fonnx instance is initialized (should have been done in start())
      final fonnx = _fonnx ??= Fonnx();
      // Use the appropriate method based on isolate type
      // Default to miniLm if type is not set (shouldn't happen, but be safe)
      // Note: outputName is ignored on Android/iOS as method channels don't support it
      // The native implementation should handle the correct output name
      final result = (_type == OnnxIsolateType.minishLab)
          ? await fonnx.minishLab(
              modelPath: modelPath,
              inputs: tokens,
            )
          : await fonnx.miniLm(
              modelPath: modelPath,
              inputs: tokens,
            );
      if (result == null) {
        throw Exception('Embeddings returned from platform code are null');
      }
      return result;
    }
    
    // On desktop platforms, ensure isolate is started
    if (_sendPort == null) {
      throw StateError(
        'OnnxIsolateManager not started. Call start() before sendInference().'
      );
    }
    
    // On desktop platforms, use the isolate
    final response = ReceivePort();
    final message = OnnxIsolateMessage(
      replyPort: response.sendPort,
      modelPath: modelPath,
      tokens: tokens,
      ortDylibPathOverride: ortDylibPathOverride,
      outputName: outputName,
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
    _isolate?.kill(priority: Isolate.immediate);
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
        // On Android/iOS, the isolate should not be used - use platform channels instead
        // This check prevents FFI errors on Android
        if (Platform.isAndroid || Platform.isIOS) {
          throw Exception(
            'Android and iOS run using platform-specific implementations via method channels, not FFI isolates. '
            'Use Fonnx().miniLm() instead of OnnxIsolateManager on these platforms.'
          );
        }
        
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
          outputName: message.outputName,
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
  List<int> tokens, {
  String? outputName,
}) async {
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
  final inputIdName = 'input_ids'.toNativeUtf8();
  inputNamesPointer[0] = inputIdName.cast();
  final tokenTypeName = 'token_type_ids'.toNativeUtf8();
  inputNamesPointer[1] = tokenTypeName.cast();
  final attentionMaskName = 'attention_mask'.toNativeUtf8();
  inputNamesPointer[2] = attentionMaskName.cast();
  final inputNames = inputNamesPointer.cast<Pointer<Char>>();
  final inputValues = calloc<Pointer<OrtValue>>(3);
  inputValues[0] = inputIdsValue.value;
  inputValues[1] = tokenTypeValue.value;
  inputValues[2] = inputMaskValue.value;

  final outputNamesPointer = calloc<Pointer<Char>>();
  // Use provided output name, or default to 'last_hidden_state' for backward compatibility
  final embeddingsName = (outputName ?? 'last_hidden_state').toNativeUtf8();
  outputNamesPointer[0] = embeddingsName.cast();

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

  session.api.releaseMemoryInfo(memoryInfo.value);
  calloc.free(memoryInfo);
  session.api.releaseValue(inputIdsValue.value);
  calloc.free(inputIdsValue);
  session.api.releaseValue(inputMaskValue.value);
  calloc.free(inputMaskValue);
  session.api.releaseValue(tokenTypeValue.value);
  calloc.free(tokenTypeValue);
  calloc.free(inputNamesPointer);
  calloc.free(inputValues);
  calloc.free(outputNamesPointer);
  calloc.free(outputValuesPtr);
  calloc.free(inputIdName);
  calloc.free(tokenTypeName);
  calloc.free(attentionMaskName);
  calloc.free(embeddingsName);
  session.api.releaseRunOptions(runOptionsPtr.value);
  calloc.free(runOptionsPtr);
  calloc.free(outputTensorDataPointer);
  session.api.releaseTensorTypeAndShapeInfo(tensorTypeAndShape.value);
  calloc.free(tensorTypeAndShape);
  calloc.free(tensorShapeElementCount);

  return floatList;
}

void ortMinishLabIsolateEntryPoint(SendPort mainSendPort) {
  final receivePort = ReceivePort();
  mainSendPort.send(receivePort.sendPort);

  OrtSessionObjects? ortSessionObjects;

  receivePort.listen((dynamic message) async {
    if (message is OnnxIsolateMessage) {
      try {
        // On Android/iOS, the isolate should not be used - use platform channels instead
        // This check prevents FFI errors on Android
        if (Platform.isAndroid || Platform.isIOS) {
          throw Exception(
            'Android and iOS run using platform-specific implementations via method channels, not FFI isolates. '
            'Use Fonnx().minishLab() instead of OnnxIsolateManager on these platforms.'
          );
        }
        
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
          outputName: message.outputName,
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
  List<int> tokens, {
  String? outputName,
}) async {
  final memoryInfo = calloc<Pointer<OrtMemoryInfo>>();
  session.api.createCpuMemoryInfo(memoryInfo);
  final inputIdsValue = calloc<Pointer<OrtValue>>();
  session.api.createInt64Tensor(
    inputIdsValue,
    memoryInfo: memoryInfo.value,
    values: tokens,
    // Use a 1D tensor shape as expected by the model
    shape: [tokens.length],
  );
  final inputMaskValue = calloc<Pointer<OrtValue>>();
  final attentionMaskValues = List.generate(
    tokens.length,
    (index) => 1,
    growable: false,
  );
  session.api.createInt64Tensor(
    inputMaskValue,
    memoryInfo: memoryInfo.value,
    values: attentionMaskValues,
    // Use a 1D tensor shape as expected by the model
    shape: [attentionMaskValues.length],
  );
  final tokenTypeValue = calloc<Pointer<OrtValue>>();
  session.api.createInt64Tensor(
    tokenTypeValue,
    memoryInfo: memoryInfo.value,
    values: List.generate(1, (index) => 0, growable: false),
    // Use a 1D tensor shape as expected by the model
    shape: [1],
  );
  final inputNamesPointer = calloc<Pointer<Pointer<Char>>>(2);
  final inputIdName = 'input_ids'.toNativeUtf8();
  inputNamesPointer[0] = inputIdName.cast();
  final tokenTypeName = 'offsets'.toNativeUtf8();
  inputNamesPointer[1] = tokenTypeName.cast();
  // final attentionMaskName = 'attention_mask'.toNativeUtf8();
  // inputNamesPointer[2] = attentionMaskName.cast();
  final inputNames = inputNamesPointer.cast<Pointer<Char>>();
  final inputValues = calloc<Pointer<OrtValue>>(2);
  inputValues[0] = inputIdsValue.value;
  inputValues[1] = tokenTypeValue.value;
  // inputValues[2] = inputMaskValue.value;

  final outputNamesPointer = calloc<Pointer<Char>>();
  // Use provided output name, or default to 'last_hidden_state' for backward compatibility
  final embeddingsName = (outputName ?? 'last_hidden_state').toNativeUtf8();
  outputNamesPointer[0] = embeddingsName.cast();

  final outputValuesPtr = calloc<Pointer<OrtValue>>();
  final outputValues = outputValuesPtr.cast<Pointer<OrtValue>>();
  final runOptionsPtr = calloc<Pointer<OrtRunOptions>>();
  session.api.createRunOptions(runOptionsPtr);
  session.api.run(
    session: session.sessionPtr.value,
    runOptions: runOptionsPtr.value,
    inputNames: inputNames,
    inputValues: inputValues,
    inputCount: 2,
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

  session.api.releaseMemoryInfo(memoryInfo.value);
  calloc.free(memoryInfo);
  session.api.releaseValue(inputIdsValue.value);
  calloc.free(inputIdsValue);
  session.api.releaseValue(inputMaskValue.value);
  calloc.free(inputMaskValue);
  session.api.releaseValue(tokenTypeValue.value);
  calloc.free(tokenTypeValue);
  calloc.free(inputNamesPointer);
  calloc.free(inputValues);
  calloc.free(outputNamesPointer);
  calloc.free(outputValuesPtr);
  calloc.free(inputIdName);
  calloc.free(tokenTypeName);
  // calloc.free(attentionMaskName);
  calloc.free(embeddingsName);
  session.api.releaseRunOptions(runOptionsPtr.value);
  calloc.free(runOptionsPtr);
  calloc.free(outputTensorDataPointer);
  session.api.releaseTensorTypeAndShapeInfo(tensorTypeAndShape.value);
  calloc.free(tensorTypeAndShape);
  calloc.free(tensorShapeElementCount);

  return floatList;
}
