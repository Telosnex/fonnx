import 'dart:isolate';
import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:fonnx/models/piper/piper.dart';
import 'package:fonnx/onnx/ort_ffi_bindings.dart' hide calloc, free;
import 'package:fonnx/onnx/ort.dart';
import 'package:fonnx/piper/piper_models.dart';

class PiperIsolateMessage {
  final SendPort replyPort;
  final String modelPath;
  final List<int> phonemes;
  final PiperSynthesisConfig config;

  PiperIsolateMessage({
    required this.replyPort,
    required this.modelPath,
    required this.phonemes,
    required this.config,
  });
}

void ortPiperIsolateEntryPoint(SendPort mainSendPort) {
  final receivePort = ReceivePort();
  mainSendPort.send(receivePort.sendPort);

  OrtSessionObjects? ortSessionObjects;

  receivePort.listen((dynamic message) async {
    if (message is PiperIsolateMessage) {
      try {
        // Lazily create the Ort session if it's not already done.
        ortSessionObjects ??= createOrtSession(message.modelPath);
        // Perform the inference here using ortSessionObjects and message.tokens, retrieve result.
        final result = await _getTextToSpeech(
          ortSessionObjects!,
          message.config,
          message.phonemes,
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
  if (ortSessionObjects == null) {
    return;
  }
  // Cleanup the Ort session? Currently we assume that the session is desired
  // for the lifetime of the application. Makes sense for embeddings models.
  // _Maybe_ Whisper. Definitely not an LLM.
}

class PiperIsolateManager {
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
      ortPiperIsolateEntryPoint,
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
    PiperSynthesisConfig config,
    List<int> tokens,
  ) async {
    final response = ReceivePort();
    final message = PiperIsolateMessage(
      replyPort: response.sendPort,
      config: config,
      modelPath: modelPath,
      phonemes: tokens,
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
          'Unknown error occurred in the ONNX isolate. ${result.runtimeType} $result');
    }
  }

  // Shut down the isolate.
  void stop() {
    _sendPort?.send('close');
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
  }
}

Future<Float32List> _getTextToSpeech(
  OrtSessionObjects session,
  PiperSynthesisConfig config,
  List<int> phonemeIds,
) async {
  final memoryInfo = calloc<Pointer<OrtMemoryInfo>>();
  session.api.createCpuMemoryInfo(memoryInfo);

  final phonemeIdsValue = calloc<Pointer<OrtValue>>();
  session.api.createInt64Tensor(
    phonemeIdsValue,
    memoryInfo: memoryInfo.value,
    values: phonemeIds,
  );

  // Setting the length and scale inputs (assuming you would have already created these values)
  final phonemeLengths = [phonemeIds.length];
  final phonemeLengthsValue = calloc<Pointer<OrtValue>>();
  session.api.createSingleRankInt64Tensor(
    phonemeLengthsValue,
    memoryInfo: memoryInfo.value,
    values: phonemeLengths,
  );

  final scales =
      Float32List.fromList([config.noiseScale, config.lengthScale, config.noiseW]); // Example scales
  print('scale: $scales');
  final scalesValue = calloc<Pointer<OrtValue>>();
  session.api.createFloat32Tensor(
    scalesValue,
    memoryInfo: memoryInfo.value,
    values: scales,
  );

  final speakerId = List.filled(1, 0); // Assuming default 0
  final speakerIdValue = calloc<Pointer<OrtValue>>();
  session.api.createSingleRankInt64Tensor(
    speakerIdValue,
    memoryInfo: memoryInfo.value,
    values: speakerId,
  );

  final inputNamesPointer = calloc<Pointer<Pointer<Char>>>(4);
  inputNamesPointer[0] = 'input'.toNativeUtf8().cast();
  inputNamesPointer[1] = 'input_lengths'.toNativeUtf8().cast();
  inputNamesPointer[2] = 'scales'.toNativeUtf8().cast();
  inputNamesPointer[3] = 'sid'.toNativeUtf8().cast();
  final inputNames = inputNamesPointer.cast<Pointer<Char>>();

  final inputValues = calloc<Pointer<OrtValue>>(4);
  inputValues[0] = phonemeIdsValue.value;
  inputValues[1] = phonemeLengthsValue.value;
  inputValues[2] = scalesValue.value;
  inputValues[3] = speakerIdValue.value;

  // Define output names and allocate pointers for output values
  final outputNamesPointer = calloc<Pointer<Char>>();
  outputNamesPointer.value =
      'output'.toNativeUtf8().cast(); // Output tensor name as per your model

  final outputValuesPtr = calloc<Pointer<OrtValue>>();
  final runOptionsPtr = calloc<Pointer<OrtRunOptions>>();
  session.api.createRunOptions(runOptionsPtr);

  // Run the inference
  session.api.run(
    session: session.sessionPtr.value,
    runOptions: runOptionsPtr.value,
    inputNames: inputNames,
    inputValues: inputValues,
    inputCount: 4,
    outputNames: outputNamesPointer,
    outputCount: 1,
    outputValues: outputValuesPtr,
  );

  // Extracting output tensor
  final outputTensorDataPointer = calloc<Pointer<Void>>();
  session.api
      .getTensorMutableData(outputValuesPtr.value, outputTensorDataPointer);
  final outputTensorDataPtr = outputTensorDataPointer.value.cast<Float>();

  final tensorTypeAndShape = calloc<Pointer<OrtTensorTypeAndShapeInfo>>();
  session.api.getTensorTypeAndShape(outputValuesPtr.value, tensorTypeAndShape);
  final tensorShapeElementCount = calloc<Size>();
  session.api.getTensorShapeElementCount(
      tensorTypeAndShape.value, tensorShapeElementCount);
  final elementCount = tensorShapeElementCount.value;

  final floatList = outputTensorDataPtr.asTypedList(elementCount);

  final audioDataList = floatList;
  var maxAudioValue = 0.01; // Start from a small non-zero value
  for (var i = 0; i < audioDataList.length; i++) {
    var audioValue = audioDataList[i].abs();
    if (audioValue > maxAudioValue) {
      maxAudioValue = audioValue;
    }
  }

  const kMaxWavValue = 32767.0;
  final audioScale = kMaxWavValue / maxAudioValue;
  final int16AudioBuffer = Int16List(elementCount);

  for (var i = 0; i < elementCount; i++) {
    var scaledValue = (audioDataList[i] * audioScale)
        .clamp(-kMaxWavValue, kMaxWavValue)
        .toInt();
    int16AudioBuffer[i] = scaledValue.toSigned(16);
  }

  // Clean up
  calloc.free(memoryInfo);
  calloc.free(phonemeIdsValue);
  calloc.free(phonemeLengthsValue);
  calloc.free(scalesValue);
  calloc.free(speakerIdValue);
  calloc.free(runOptionsPtr);
  calloc.free(outputValuesPtr);
  calloc.free(outputTensorDataPointer);
  calloc.free(tensorTypeAndShape);
  calloc.free(tensorShapeElementCount);

  return Float32List.fromList(floatList);
}
