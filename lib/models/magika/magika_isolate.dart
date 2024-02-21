import 'dart:isolate';
import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:fonnx/dylib_path_overrides.dart';
import 'package:fonnx/onnx/ort_ffi_bindings.dart' hide calloc, free;
import 'package:fonnx/onnx/ort.dart';

class MagikaIsolateMessage {
  final SendPort replyPort;
  final String modelPath;
  final String? ortDylibPathOverride;
  final List<int> bytes;

  MagikaIsolateMessage({
    required this.replyPort,
    required this.modelPath,
    required this.bytes,
    this.ortDylibPathOverride,
  });
}

void magikaIsolateEntryPoint(SendPort mainSendPort) {
  final receivePort = ReceivePort();
  mainSendPort.send(receivePort.sendPort);

  OrtSessionObjects? ortSessionObjects;

  receivePort.listen((dynamic message) async {
    if (message is MagikaIsolateMessage) {
      try {
        // Set the global constant because its a different global on the
        // isolate.
        if (message.ortDylibPathOverride != null) {
          fonnxOrtDylibPathOverride = message.ortDylibPathOverride;
        }
        // Lazily create the Ort session if it's not already done.
        ortSessionObjects ??=
            createOrtSession(message.modelPath, includeOnnxExtensionsOps: true);
        // Perform the inference here using ortSessionObjects and message.tokens, retrieve result.
        final result =
            await _getMagikaResultVector(ortSessionObjects!, message.bytes);
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
}

class MagikaIsolateManager {
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
      magikaIsolateEntryPoint,
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
    List<int> bytes, {
    String? ortDylibPathOverride,
    String? ortExtensionsDylibPathOverride,
  }) async {
    await start();
    final response = ReceivePort();
    final message = MagikaIsolateMessage(
      replyPort: response.sendPort,
      modelPath: modelPath,
      bytes: bytes,
      ortDylibPathOverride: ortDylibPathOverride,
    );

    _sendPort!.send(message);
    // This will wait for a response from the isolate.
    final dynamic result = await response.first;
    if (result is Float32List) {
      return result;
    } else if (result is Error || result is Exception) {
      throw result;
    } else {
      throw Exception(
          'Unknown error occurred in the ONNX isolate. Output was runtime type: ${result.runtimeType}');
    }
  }

  // Shut down the isolate.
  void stop() {
    _sendPort?.send('close');
    _isolate?.kill(priority: Isolate.immediate);
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
Future<Float32List> _getMagikaResultVector(
  OrtSessionObjects session,
  List<int> bytes,
) async {
  // Inputs:
  // - bytes: file bytes, example code takes 512 bytes from 3 chunks of file.
  //    float32[batch, 1536]
  // Outputs:
  // - target_label: float32[batch, 113]

  final memoryInfo = calloc<Pointer<OrtMemoryInfo>>();
  session.api.createCpuMemoryInfo(memoryInfo);
  final inputValue = calloc<Pointer<OrtValue>>();
  session.api.createFloat32Tensor2DFromInts(
    inputValue,
    memoryInfo: memoryInfo.value,
    values: [bytes]
  );
  const kInputCount = 1;
  final inputNamesPointer = calloc<Pointer<Pointer<Char>>>(kInputCount);
  inputNamesPointer[0] = 'bytes'.toNativeUtf8().cast();
  final inputNames = inputNamesPointer.cast<Pointer<Char>>();
  final inputValues = calloc<Pointer<OrtValue>>(kInputCount);
  inputValues[0] = inputValue.value;

  const kOutputCount = 1;
  final outputNamesPointer = calloc<Pointer<Pointer<Char>>>(kOutputCount);
  outputNamesPointer[0] = 'target_label'.toNativeUtf8().cast();
  final outputNames = outputNamesPointer.cast<Pointer<Char>>();
  final outputValues = calloc<Pointer<OrtValue>>(kOutputCount);
  final runOptionsPtr = calloc<Pointer<OrtRunOptions>>();
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

  final tensorDataPointer = calloc<Pointer<Void>>();
  session.api.getTensorMutableData(outputValues[0], tensorDataPointer);
  final floatsPtr = tensorDataPointer.value.cast<Float>();
  final tensorTypeAndShape = calloc<Pointer<OrtTensorTypeAndShapeInfo>>();
  session.api.getTensorTypeAndShape(outputValues[0], tensorTypeAndShape);
  final tensorShapeElementCount = calloc<Size>();
  session.api.getTensorShapeElementCount(
      tensorTypeAndShape.value, tensorShapeElementCount);
  final elementCount = tensorShapeElementCount.value;
  final floatList = floatsPtr.asTypedList(elementCount);
  return floatList;
}
