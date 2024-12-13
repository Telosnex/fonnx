import 'dart:isolate';
import 'dart:async';
import 'dart:ffi';
import 'dart:math';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:fonnx/dylib_path_overrides.dart';
import 'package:fonnx/onnx/ort_ffi_bindings.dart' hide calloc, free;
import 'package:fonnx/onnx/ort.dart';

/// Message class for Pyannote isolate communication.
///
/// Encapsulates all data needed for processing audio in an isolate.
class PyannoteIsolateMessage {
  /// Port to send results back to main isolate
  final SendPort replyPort;

  /// Path to the ONNX model file
  final String modelPath;

  /// Optional override for ONNX Runtime library path
  final String? ortDylibPathOverride;

  /// Raw audio data as float32 samples
  final Float32List audioData;


  /// Creates a new isolate message.
  ///
  /// All parameters except [ortDylibPathOverride] are required.
  PyannoteIsolateMessage({
    required this.replyPort,
    required this.modelPath,
    required this.audioData,
    this.ortDylibPathOverride,
  });
}

/// Exception thrown by PyannoteONNX operations.
class PyannoteException implements Exception {
  /// Error message describing the issue
  final String message;

  /// Original error that caused this exception, if any
  final dynamic originalError;

  /// Creates a new PyannoteException.
  ///
  /// [message] describes the error condition.
  /// [originalError] is the underlying error, if any.
  PyannoteException(this.message, [this.originalError]);

  @override
  String toString() =>
      'PyannoteException: $message${originalError != null ? '\nOriginal error: $originalError' : ''}';
}

/// Main class for speaker diarization using Pyannote ONNX models.
///
/// Provides functionality to process audio and detect speaker segments using
/// Pyannote ONNX model for segmentation-3.0.
class PyannoteONNX {
  /// Sample rate required by all Pyannote models (16kHz)
  static const int sampleRate = 16000;
  static const int duration = 10 * 16000; // Fixed 10 seconds window
  static const int numSpeakers = 3; // Fixed 3 speakers

  /// Whether to show processing progress
  final bool showProgress;

  /// Path to the ONNX model file
  final String _modelPath;

  /// Manager for isolate communication
  final PyannoteIsolateManager _isolateManager;

  /// Creates a new PyannoteONNX instance from a model file.
  PyannoteONNX({
    required String modelPath,
    this.showProgress = false,
  })  : _modelPath = modelPath,
        _isolateManager = PyannoteIsolateManager();

  /// Processes audio data and returns speaker segments.
  ///
  /// [audioData] should be a Float32List of audio samples at 16kHz.
  ///
  /// Returns a list of segments in the format:
  /// ```dart
  /// {
  ///   'speaker': int,    // Speaker index (0-2)
  ///   'start': double,   // Start time in seconds
  ///   'stop': double,    // End time in seconds
  /// }
  /// ```
  Future<List<Map<String, dynamic>>> process(Float32List audioData) async {
    if (audioData.isEmpty) {
      throw PyannoteException('Audio data cannot be empty');
    }

    try {
      return await _isolateManager.sendInference(_modelPath, audioData);
    } catch (e) {
      throw PyannoteException('Failed to process audio', e);
    } finally {
      _isolateManager.stop();
    }
  }

  /// Releases resources used by this instance.
  void dispose() {
    _isolateManager.stop();
  }
}

/// Manages communication with the processing isolate.
///
/// Handles starting/stopping the isolate and sending messages for inference.
class PyannoteIsolateManager {
  /// Port for sending messages to the isolate
  SendPort? _sendPort;

  /// The processing isolate
  Isolate? _isolate;

  /// Future that completes when the isolate is started
  Future<void>? _starting;

  /// Starts the processing isolate if not already running.
  Future<void> start() async {
    if (_starting != null) {
      await _starting;
      return;
    }
    if (_isolate != null) {
      return;
    }

    final completer = Completer<void>();
    _starting = completer.future;

    final receivePort = ReceivePort();
    _isolate = await Isolate.spawn(
      pyannoteIsolateEntryPoint,
      receivePort.sendPort,
      onError: receivePort.sendPort,
    );

    final sendPort = await receivePort.first as SendPort;
    _sendPort = sendPort;

    completer.complete();
    _starting = null;
  }

  /// Sends audio data for inference.
  ///
  /// Returns the processed segments.
  /// Throws if the isolate encounters an error.
  Future<List<Map<String, dynamic>>> sendInference(
    String modelPath,
    Float32List audioData, {
    String? ortDylibPathOverride,
  }) async {
    await start();
    final response = ReceivePort();

    final message = PyannoteIsolateMessage(
      replyPort: response.sendPort,
      modelPath: modelPath,
      audioData: audioData,
      ortDylibPathOverride: ortDylibPathOverride,
    );

    _sendPort!.send(message);

    final dynamic result = await response.first;
    if (result is List<Map<String, dynamic>>) {
      return result;
    } else if (result is Error) {
      throw result;
    } else if (result is PyannoteException) {
      throw result;
    } else {
      throw Exception(
        'Unknown error in Pyannote isolate. Output type: ${result.runtimeType} ${result.toString()}',
      );
    }
  }

  /// Stops the processing isolate.
  void stop() {
    _sendPort?.send('close');
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
  }
}

/// Entry point for the processing isolate.
///
/// Sets up message handling and ONNX session management.
void pyannoteIsolateEntryPoint(SendPort mainSendPort) {
  final receivePort = ReceivePort();
  mainSendPort.send(receivePort.sendPort);

  OrtSessionObjects? ortSessionObjects;

  receivePort.listen((dynamic message) async {
    if (message is PyannoteIsolateMessage) {
      try {
        if (message.ortDylibPathOverride != null) {
          fonnxOrtDylibPathOverride = message.ortDylibPathOverride;
        }

        ortSessionObjects ??= createOrtSession(
          message.modelPath,
          includeOnnxExtensionsOps: true,
        );

        final result = await _processAudioInIsolate(
          ortSessionObjects!,
          message.audioData,
        );

        message.replyPort.send(result);
      } catch (e) {
        message.replyPort.send(e);
      }
    } else if (message == 'close') {
      if (ortSessionObjects != null) {
        cleanupOrtSession(ortSessionObjects);
      }
      Isolate.exit();
    } else {
      throw Exception('Unknown message received in Pyannote isolate.');
    }
  });
}

/// Cleans up resources associated with an ORT session.
///
/// Ensures proper deallocation of memory used by the ONNX Runtime session.
void cleanupOrtSession(OrtSessionObjects? ortSessionObjects) {
  if (ortSessionObjects == null) {
    return;
  }
  // TODO: Implement cleanup
}

/// Processes audio data in the isolate.
Future<List<Map<String, dynamic>>> _processAudioInIsolate(
  OrtSessionObjects session,
  Float32List audioData,
) async {
  try {
    final step = (PyannoteONNX.duration ~/ 2).clamp(
      PyannoteONNX.duration ~/ 2,
      (0.9 * PyannoteONNX.duration).toInt(),
    );

    final memoryInfo = calloc<Pointer<OrtMemoryInfo>>();
    session.api.createCpuMemoryInfo(memoryInfo);

    List<Map<String, dynamic>> results = [];
    List<bool> isActive = List.filled(PyannoteONNX.numSpeakers, false);
    List<int> startSamples = List.filled(PyannoteONNX.numSpeakers, 0);
    // Add near where isActive and startSamples are declared
    final probSums = List<double>.filled(PyannoteONNX.numSpeakers, 0.0);
    final framesCounted = List<int>.filled(PyannoteONNX.numSpeakers, 0);
    int currentSamples = 721;

    final overlap = sample2frame(PyannoteONNX.duration - step);
    var overlapChunk = List.generate(
      overlap,
      (_) => List.filled(PyannoteONNX.numSpeakers, 0.0),
    );

    final windows = slidingWindow(
      audioData,
      PyannoteONNX.duration,
      step,
    ).toList();

    for (int idx = 0; idx < windows.length; idx++) {
      final (windowSize, window) = windows[idx];
      // Prepare input tensor
      final inputValue = calloc<Pointer<OrtValue>>();
      session.api.createFloat32Tensor3D(
        inputValue,
        memoryInfo: memoryInfo.value,
        values: [
          [window]
        ],
      );

      // Run inference
      final outputValue = calloc<Pointer<OrtValue>>();
      final inputNamesPtr = calloc<Pointer<Pointer<Char>>>();
      inputNamesPtr.value = calloc<Pointer<Char>>();
      inputNamesPtr.value[0] = 'input_values'.toNativeUtf8().cast();

      final inputValuesPtr = calloc<Pointer<OrtValue>>();
      inputValuesPtr[0] = inputValue.value;

      final outputNamesPtr = calloc<Pointer<Pointer<Char>>>();
      outputNamesPtr.value = calloc<Pointer<Char>>();
      outputNamesPtr.value[0] = 'logits'.toNativeUtf8().cast();

      final runOptionsPtr = calloc<Pointer<OrtRunOptions>>();
      session.api.createRunOptions(runOptionsPtr);

      session.api.run(
        session: session.sessionPtr.value,
        runOptions: runOptionsPtr.value,
        inputNames: inputNamesPtr.value,
        inputValues: inputValuesPtr,
        inputCount: 1,
        outputNames: outputNamesPtr.value,
        outputValues: outputValue,
        outputCount: 1,
      );

      // Extract output data
      final tensorDataPointer = calloc<Pointer<Void>>();
      session.api.getTensorMutableData(outputValue.value, tensorDataPointer);
      final floatsPtr = tensorDataPointer.value.cast<Float>();
      final tensorTypeAndShape = calloc<Pointer<OrtTensorTypeAndShapeInfo>>();
      session.api.getTensorTypeAndShape(outputValue.value, tensorTypeAndShape);

      final tensorShapeElementCount = calloc<Size>();
      session.api.getTensorShapeElementCount(
        tensorTypeAndShape.value,
        tensorShapeElementCount,
      );

      var outputData = floatsPtr.asTypedList(tensorShapeElementCount.value);
      List<List<double>> frameOutputs = [];

      final numCompleteFrames = outputData.length ~/ 7;
      for (int frame = 0; frame < numCompleteFrames; frame++) {
        final i = frame * 7;
        var probs = outputData.sublist(i, i + 7).map((x) => exp(x)).toList();

        var speakerProbs = List<double>.filled(3, 0.0);
        speakerProbs[0] = probs[1] + probs[4] + probs[5]; // spk1
        speakerProbs[1] = probs[2] + probs[4] + probs[6]; // spk2
        speakerProbs[2] = probs[3] + probs[5] + probs[6]; // spk3

        frameOutputs.add(speakerProbs);
      }

      if (idx > 0) {
        frameOutputs = reorder(overlapChunk, frameOutputs);
        for (int i = 0; i < overlap; i++) {
          for (int j = 0; j < PyannoteONNX.numSpeakers; j++) {
            frameOutputs[i][j] = (frameOutputs[i][j] + overlapChunk[i][j]) / 2;
          }
        }
      }

      if (idx < windows.length - 1) {
        overlapChunk = frameOutputs.sublist(frameOutputs.length - overlap);
        frameOutputs = frameOutputs.sublist(0, frameOutputs.length - overlap);
      } else {
        frameOutputs = frameOutputs.sublist(
          0,
          min(frameOutputs.length, sample2frame(windowSize)),
        );
      }

      // Process frames and track speaker segments
      for (var probs in frameOutputs) {
        currentSamples += 270;
        for (int spk = 0; spk < PyannoteONNX.numSpeakers; spk++) {
          if (isActive[spk]) {
            // Add probability tracking
            probSums[spk] += probs[spk];
            framesCounted[spk]++;
            
            if (probs[spk] < 0.5) {
              results.add({
                'speaker': spk,
                'start': startSamples[spk] / PyannoteONNX.sampleRate,
                'stop': currentSamples / PyannoteONNX.sampleRate,
                'probability': probSums[spk] / framesCounted[spk], // Add average probability
              });
              isActive[spk] = false;
              // Reset tracking for this speaker
              probSums[spk] = 0.0;
              framesCounted[spk] = 0;
            }
          } else {
            if (probs[spk] > 0.5) {
              startSamples[spk] = currentSamples;
              isActive[spk] = true;
              // Start tracking probability
              probSums[spk] = probs[spk];
              framesCounted[spk] = 1;
            }
          }
        }
      }

      // Cleanup ONNX resources
      calloc.free(tensorDataPointer);
      calloc.free(tensorTypeAndShape);
      calloc.free(tensorShapeElementCount);
      calloc.free(inputValue);
      calloc.free(outputValue);
    }

    for (int spk = 0; spk < PyannoteONNX.numSpeakers; spk++) {
      if (isActive[spk]) {
        results.add({
          'speaker': spk,
          'start': startSamples[spk] / PyannoteONNX.sampleRate,
          'stop': currentSamples / PyannoteONNX.sampleRate,
          'probability': probSums[spk] / framesCounted[spk], // Add average probability
        });
      }
    }

    calloc.free(memoryInfo);
    return results;
  } catch (e, s) {
    throw PyannoteException('Failed to process audio in isolate. Stack: $s', e);
  }
}

/// Converts sample count to frame count.
///
/// Accounts for the model's internal striding and padding.
int sample2frame(int x) => (x - 721) ~/ 270;

/// Converts frame count to sample count.
///
/// Inverse of [sample2frame].
int frame2sample(int x) => (x * 270) + 721;

/// Generates sliding windows over the audio data.
///
/// Returns an iterable of tuples containing:
/// - Window size in samples
/// - Window data as Float32List
///
/// The last window may be padded if it's incomplete.
Iterable<(int, Float32List)> slidingWindow(
  Float32List waveform,
  int windowSize,
  int stepSize,
) sync* {
  int start = 0;
  final numSamples = waveform.length;

  // Process full windows
  while (start <= numSamples - windowSize) {
    yield (
      windowSize,
      Float32List.sublistView(waveform, start, start + windowSize),
    );
    start += stepSize;
  }

  // Handle last incomplete window if needed
  if (numSamples < windowSize || (numSamples - windowSize) % stepSize > 0) {
    final lastWindow = Float32List.sublistView(waveform, start);
    final lastWindowSize = lastWindow.length;

    if (lastWindowSize < windowSize) {
      // Create padded window
      final paddedWindow = Float32List(windowSize);
      paddedWindow.setAll(0, lastWindow);
      // Remaining elements are already 0 by default
      yield (lastWindowSize, paddedWindow);
    } else {
      yield (lastWindowSize, lastWindow);
    }
  }
}

/// Reorders speaker assignments for consistency.
///
/// Takes two consecutive sets of speaker probabilities and finds the
/// permutation that minimizes differences between them.
List<List<double>> reorder(List<List<double>> x, List<List<double>> y) {
  final perms = _generatePermutations(PyannoteONNX.numSpeakers);

  List<List<double>> yTransposed = List.generate(
    PyannoteONNX.numSpeakers,
    (i) => List.generate(y.length, (j) => y[j][i]),
  );

  double minDiff = double.infinity;
  List<List<double>> bestPerm = y;

  for (var perm in perms) {
    var permuted = List.generate(
      y.length,
      (i) => List.generate(
        PyannoteONNX.numSpeakers,
        (j) => yTransposed[perm[j]][i],
      ),
    );

    double diff = 0;
    for (int i = 0; i < x.length; i++) {
      for (int j = 0; j < PyannoteONNX.numSpeakers; j++) {
        diff += (x[i][j] - permuted[i][j]).abs();
      }
    }

    if (diff < minDiff) {
      minDiff = diff;
      bestPerm = permuted;
    }
  }

  return bestPerm;
}

/// Generates all possible permutations of speaker assignments.
List<List<int>> _generatePermutations(int n) {
  if (n == 1) {
    return [
      [0]
    ];
  }

  List<List<int>> result = [];
  for (int i = 0; i < n; i++) {
    var subPerms = _generatePermutations(n - 1);
    for (var perm in subPerms) {
      var newPerm = [i, ...perm.map((x) => x >= i ? x + 1 : x)];
      result.add(newPerm);
    }
  }
  return result;
}
