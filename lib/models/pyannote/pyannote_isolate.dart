import 'dart:isolate';
import 'dart:async';
import 'dart:ffi';
import 'dart:math';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:fonnx/dylib_path_overrides.dart';
import 'package:fonnx/onnx/ort_ffi_bindings.dart' hide calloc, free;
import 'package:fonnx/onnx/ort.dart';

/// Configuration for different Pyannote model variants.
///
/// Specifies the duration window and number of speakers for each model type.
class PyannoteConfig {
  /// Duration window in seconds
  final int duration;

  /// Number of speakers the model can detect
  final int numSpeakers;

  /// Creates a new PyannoteConfig.
  ///
  /// [duration] is in seconds.
  /// [numSpeakers] is the maximum number of concurrent speakers.
  const PyannoteConfig({
    required this.duration,
    required this.numSpeakers,
  });
}

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

  /// Configuration parameters for processing
  final Map<String, dynamic> config;

  /// Creates a new isolate message.
  ///
  /// All parameters except [ortDylibPathOverride] are required.
  PyannoteIsolateMessage({
    required this.replyPort,
    required this.modelPath,
    required this.audioData,
    required this.config,
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
/// various Pyannote model variants. Supports multiple speakers and different
/// segmentation approaches.
class PyannoteONNX {
  /// Sample rate required by all Pyannote models (16kHz)
  static const int sampleRate = 16000;

  /// Name of the model variant being used
  final String modelName;

  /// Whether to show processing progress
  final bool showProgress;

  /// Path to the ONNX model file
  final String _modelPath;

  /// Manager for isolate communication
  final PyannoteIsolateManager _isolateManager;

  /// Configuration for the selected model
  late final PyannoteConfig _config;


  /// Available model configurations
  static const Map<String, PyannoteConfig> configs = {
    'segmentation': PyannoteConfig(duration: 5, numSpeakers: 3),
    'segmentation-3.0': PyannoteConfig(duration: 10, numSpeakers: 3),
    'segmentation_bigdata': PyannoteConfig(duration: 5, numSpeakers: 4),
    'short_scd_bigdata': PyannoteConfig(duration: 5, numSpeakers: 1),
  };

  /// Creates a new PyannoteONNX instance from a model file.
  ///
  /// [modelPath] must point to a valid ONNX model file.
  /// [modelName] must be one of the supported model types.
  /// [showProgress] enables progress reporting (default: false).
  ///
  /// Throws [PyannoteException] if the model type is not supported.
  factory PyannoteONNX.fromPath({
    required String modelPath,
    required String modelName,
    bool showProgress = false,
  }) {
    if (!configs.containsKey(modelName)) {
      throw PyannoteException(
        'Unsupported model type: $modelName. Must be one of: ${configs.keys.join(", ")}',
      );
    }
    return PyannoteONNX._(modelPath, modelName, showProgress);
  }

  /// Internal constructor.
  PyannoteONNX._(this._modelPath, this.modelName, this.showProgress)
      : _isolateManager = PyannoteIsolateManager() {
    _config = configs[modelName]!;
  }

  /// Processes audio data and returns speaker segments.
  ///
  /// [audioData] should be a Float32List of audio samples at 16kHz.
  /// [step] optionally controls the window step size (default: duration/2).
  ///
  /// Returns a list of segments. For regular segmentation models:
  /// ```dart
  /// {
  ///   'speaker': int,    // Speaker index
  ///   'start': double,   // Start time in seconds
  ///   'stop': double,    // End time in seconds
  /// }
  /// ```
  ///
  /// For short_scd_bigdata model:
  /// ```dart
  /// {
  ///   'timestamp': double,  // Change point time in seconds
  /// }
  /// ```
  ///
  /// Throws [PyannoteException] if processing fails.
  Future<List<Map<String, dynamic>>> process(
    Float32List audioData,
    int duration,
    int numberOfSpeakers, {
    double? step,
  }) async {
    if (audioData.isEmpty) {
      throw PyannoteException('Audio data cannot be empty');
    }

    try {
      final processedData = await _isolateManager.sendInference(
        _modelPath,
        audioData,
        {
          'step': step,
          'duration': duration,
          'modelName': modelName,
          'numSpeakers': _config.numSpeakers,
        },
      );

      return processedData;
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
    Float32List audioData,
    Map<String, dynamic> config, {
    String? ortDylibPathOverride,
  }) async {
    await start();
    final response = ReceivePort();

    final message = PyannoteIsolateMessage(
      replyPort: response.sendPort,
      modelPath: modelPath,
      audioData: audioData,
      config: config,
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
          message.config,
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
  // TODO: Unimplemented cleanupOrtSession.
  if (ortSessionObjects == null) {
    return;
  }
}

/// Processes audio data in the isolate.
///
/// Handles the core ONNX inference and speaker tracking logic.
Future<List<Map<String, dynamic>>> _processAudioInIsolate(
  OrtSessionObjects session,
  Float32List audioData,
  Map<String, dynamic> config,
) async {
  try {
    final modelName = config['modelName'] as String;
    const duration = 10 * 16000; // in seconds, 10 is for segmentation-3.0
    const numSpeakers = 3; // 3 is for segmentation-3.0
    final step = (duration ~/ 2).clamp(
        duration ~/ 2, // 80000
        (0.9 * duration).toInt() // 144000
    );
    // Set up ONNX inputs
    final memoryInfo = calloc<Pointer<OrtMemoryInfo>>();
    session.api.createCpuMemoryInfo(memoryInfo);

    List<Map<String, dynamic>> results = [];
    List<bool> isActive = List.filled(numSpeakers, false);
    List<int> startSamples = List.filled(numSpeakers, 0);
    int currentSamples = 721; // Initial offset

    // Calculate overlap
    final overlap = sample2frame(duration - step);
    var overlapChunk = List.generate(
      overlap,
      (_) => List.filled(numSpeakers, 0.0),
    );
    final windows = slidingWindow(
      audioData,
      duration,
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

      // Process model-specific outputs
      if (modelName == "segmentation-3.0") {
        final numCompleteFrames = outputData.length ~/ 7;

        for (int frame = 0; frame < numCompleteFrames; frame++) {
          final i = frame * 7;
          // Just do exp() like Python, no extra normalization
          var probs = outputData.sublist(i, i + 7).map((x) => exp(x)).toList();

          var speakerProbs = List<double>.filled(3, 0.0);
          speakerProbs[0] = probs[1] + probs[4] + probs[5]; // spk1
          speakerProbs[1] = probs[2] + probs[4] + probs[6]; // spk2
          speakerProbs[2] = probs[3] + probs[5] + probs[6]; // spk3

          frameOutputs.add(speakerProbs);
        }
      } else {
        for (int i = 0; i < outputData.length; i += numSpeakers) {
          frameOutputs
              .add(List.generate(numSpeakers, (j) => outputData[i + j]));
        }
      }

      // Handle overlap between windows
      if (idx > 0) {
        frameOutputs = reorder(overlapChunk, frameOutputs);
        for (int i = 0; i < overlap; i++) {
          for (int j = 0; j < numSpeakers; j++) {
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
        if (modelName == "short_scd_bigdata") {
          if (probs[0] > 0.5 && !isActive[0]) {
            isActive[0] = true;
            results.add({
              'timestamp': currentSamples / PyannoteONNX.sampleRate,
            });
          }
          if (probs[0] < 0.5) {
            isActive[0] = false;
          }
        } else {
          for (int spk = 0; spk < numSpeakers; spk++) {
            if (isActive[spk]) {
              if (probs[spk] < 0.5) {
                results.add({
                  'speaker': spk,
                  'start': startSamples[spk] / PyannoteONNX.sampleRate,
                  'stop': currentSamples / PyannoteONNX.sampleRate,
                });
                isActive[spk] = false;
              }
            } else {
              if (probs[spk] > 0.5) {
                startSamples[spk] = currentSamples;
                isActive[spk] = true;
              }
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

    // Handle any active speakers at the end of processing
    if (modelName != "short_scd_bigdata") {
      for (int spk = 0; spk < numSpeakers; spk++) {
        if (isActive[spk]) {
          results.add({
            'speaker': spk,
            'start': startSamples[spk] / PyannoteONNX.sampleRate,
            'stop': currentSamples / PyannoteONNX.sampleRate,
          });
        }
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
  final int numSpeakers = y[0].length;
  final perms = _generatePermutations(numSpeakers);

  List<List<double>> yTransposed = List.generate(
    numSpeakers,
    (i) => List.generate(y.length, (j) => y[j][i]),
  );

  double minDiff = double.infinity;
  List<List<double>> bestPerm = y;

  for (var perm in perms) {
    var permuted = List.generate(
      y.length,
      (i) => List.generate(
        numSpeakers,
        (j) => yTransposed[perm[j]][i],
      ),
    );

    double diff = 0;
    for (int i = 0; i < x.length; i++) {
      for (int j = 0; j < numSpeakers; j++) {
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
