import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fonnx/models/sileroVad/silero_vad.dart';
import 'package:fonnx_example/padding.dart';
import 'package:fonnx_example/stt_service.dart';
import 'package:fonnx_example/whisper_widget.dart';
import 'dart:async';
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:path/path.dart' as path;

class SileroVadWidget extends StatefulWidget {
  const SileroVadWidget({super.key});

  @override
  State<SileroVadWidget> createState() => _SileroVadWidgetState();
}

class _SileroVadWidgetState extends State<SileroVadWidget> {
  bool? _verifyPassed;
  String? _speedTestResult;
  SttServiceResponse? _sttServiceResponse;
  StreamSubscription? _sttStreamSubscription;
  SttService? _sttService;
  var _sttIsVoiceThreshold = SttService.kVadPIsVoiceThreshold;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        heightPadding,
        Text(
          'Silero',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        heightPadding,
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            ElevatedButton(
              onPressed: _runVerificationTest,
              child: const Text('Test Correctness'),
            ),
            widthPadding,
            if (_verifyPassed == true)
              const Icon(
                Icons.check,
                color: Colors.green,
              ),
            if (_verifyPassed == false)
              const Icon(
                Icons.close,
                color: Colors.red,
              ),
          ],
        ),
        heightPadding,
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            ElevatedButton(
              onPressed: _runPerformanceTest,
              child: const Text('Test Speed'),
            ),
            widthPadding,
            if (_speedTestResult != null)
              Text(
                '${_speedTestResult}x realtime',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
          ],
        ),
        heightPadding,
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            ElevatedButton(
              onPressed: _runVadDemo,
              child: const Text('Demo'),
            ),
          ],
        ),
        if (_sttServiceResponse != null) ...[
          heightPadding,
          Text(
            _sttServiceResponse!.transcription,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          heightPadding,
          SizedBox(
            height: 100,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: _sttServiceResponse!.audioFrames.map((e) {
                  final Color color;
                  if (e?.vadP == null) {
                    color = Colors.transparent;
                  } else if (e!.vadP! > _sttIsVoiceThreshold) {
                    color = Colors.green;
                  } else {
                    color = Colors.red;
                  }
                  return Align(
                    alignment: Alignment.bottomCenter,
                    child: Tooltip(
                      showDuration: Duration.zero,
                      waitDuration: Duration.zero,
                      message: e?.vadP == null
                          ? 'not recorded yet'
                          : '${(e!.vadP! * 100).toStringAsFixed(0)}%',
                      child: Container(
                        width: 10,
                        height: 100 * (e?.vadP == null ? 1 : e!.vadP!),
                        color: color,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          heightPadding,
          Text(
              'Voice threshold: ${(_sttIsVoiceThreshold * 100).toStringAsFixed(0)}%'),
          Slider(
            label: '${(_sttIsVoiceThreshold * 100).toStringAsFixed(0)}%',
            value: _sttIsVoiceThreshold,
            onChanged: (value) {
              setState(
                () {
                  _sttIsVoiceThreshold = value;
                },
              );
            },
          ),
          ElevatedButton.icon(
            onPressed: () async {
              final frames = _sttServiceResponse!.audioFrames;
              int? firstFrameIndex;
              int? lastFrameIndex;
              for (var i = 0; i < frames.length; i++) {
                final frame = frames[i];
                if (frame?.vadP == null) {
                  // Audio hasn't been processed.
                  continue; // Continues to next iteration if audio hasn't been processed, instead of breaking.
                }
                // Check for the first non-silent frame
                if (firstFrameIndex == null &&
                    frame!.vadP! > _sttIsVoiceThreshold) {
                  firstFrameIndex = i;
                }
                // Update the last non-silent frame index whenever a non-silent frame is encountered
                if (frame!.vadP! > _sttIsVoiceThreshold) {
                  lastFrameIndex = i;
                }
              }
// Return or perform further actions only if both first and last non-silent frames are found
              if (firstFrameIndex == null || lastFrameIndex == null) {
                return;
              }
              final framesToProcess = frames.sublist(
                math.max(firstFrameIndex - 3, 0),
                math.min(lastFrameIndex + 10, frames.length),
              );
              debugPrint(
                  'Detected ${framesToProcess.length} frames of voice (from ${frames.whereType<AudioFrame>().toList().length} of audio @ threshold $_sttIsVoiceThreshold)');
              final wav = wavFromFrames(
                frames: framesToProcess.whereType<AudioFrame>().toList(),
                minVadP: 0,
              );
              final tempDir = await path_provider.getTemporaryDirectory();
              final wavPath = path.join(tempDir.path, 'voice.wav');
              final wavFile = File(wavPath);
              await wavFile.writeAsBytes(wav);
              final player = AudioPlayer();
              player.play(DeviceFileSource(wavPath));
            },
            icon: const Icon(Icons.play_arrow),
            label: const Text("Play"),
          ),
        ]
      ],
    );
  }

  void _runVerificationTest() async {
    final modelPath =
        await getModelPath('assets/models/sileroVad/silero_vad.onnx');
    final silero = SileroVad.load(modelPath);
    final wavFile = await rootBundle.load('assets/audio_sample_16khz.wav');
    final result = await silero.doInference(wavFile.buffer.asUint8List());
    setState(() {
      // obtained on macOS M2 9 Feb 2024.
      _verifyPassed = result.length == 3 &&
          (result['output'] as Float32List).first == 0.4739372134208679;
    });
  }

  void _runVadDemo() async {
    if (_sttStreamSubscription != null) {
      setState(() {
        _sttStreamSubscription?.cancel();
        _sttStreamSubscription = null;
        _sttService?.stop();
        _sttService = null;
      });
      return;
    }
    final vadModelPath =
        await getModelPath('assets/models/sileroVad/silero_vad.onnx');
    final whisperModelPath =
        await getWhisperModelPath('assets/models/whisper/whisper_tiny.onnx');
    final service = SttService(
        vadModelPath: vadModelPath, whisperModelPath: whisperModelPath);
    _sttService = service;
    final subscription = service.transcribe().listen((event) {
      setState(() {
        _sttServiceResponse = event;
      });
    });

    setState(() {
      _sttStreamSubscription = subscription;
    });
  }

  void _runPerformanceTest() async {
    final modelPath =
        await getModelPath('assets/models/sileroVad/silero_vad.onnx');
    final sileroVad = SileroVad.load(modelPath);
    final result = await testPerformance(sileroVad);
    setState(() {
      _speedTestResult = result;
    });
  }

  static Future<String> testPerformance(SileroVad sileroVad) async {
    final wavFile = await rootBundle.load('assets/audio_sample_16khz.wav');
    final bytes = wavFile.buffer.asUint8List();
    const iterations = 3;
    final Stopwatch sw = Stopwatch();
    for (var i = 0; i < iterations; i++) {
      if (i == 1) {
        sw.start();
      }
      await sileroVad.doInference(bytes);
    }
    sw.stop();
    debugPrint('Silero VAD performance:');
    final average =
        sw.elapsedMilliseconds.toDouble() / (iterations - 1).toDouble();
    debugPrint('  Average: ${average.toStringAsFixed(0)} ms');
    debugPrint('  Total: ${sw.elapsedMilliseconds} ms');
    const fileDurationMs = 5000;
    final speedMultilper = fileDurationMs.toDouble() / average;
    debugPrint('  Speed multiplier: ${speedMultilper.toStringAsFixed(2)}x');
    debugPrint('  Model path: ${sileroVad.modelPath}');
    return speedMultilper.toStringAsFixed(2);
  }

  Future<String> getModelPath(String modelFilenameWithExtension) async {
    if (kIsWeb) {
      return 'assets/models/sileroVad/$modelFilenameWithExtension';
    }
    final assetCacheDirectory =
        await path_provider.getApplicationSupportDirectory();
    final modelPath =
        path.join(assetCacheDirectory.path, modelFilenameWithExtension);

    File file = File(modelPath);
    bool fileExists = await file.exists();
    final fileLength = fileExists ? await file.length() : 0;

    // Do not use path package / path.join for paths.
    // After testing on Windows, it appears that asset paths are _always_ Unix style, i.e.
    // use /, but path.join uses \ on Windows.
    final assetPath =
        'assets/models/sileroVad/${path.basename(modelFilenameWithExtension)}';
    final assetByteData = await rootBundle.load(assetPath);
    final assetLength = assetByteData.lengthInBytes;
    final fileSameSize = fileLength == assetLength;
    if (!fileExists || !fileSameSize) {
      debugPrint(
          'Copying model to $modelPath. Why? Either the file does not exist (${!fileExists}), '
          'or it does exist but is not the same size as the one in the assets '
          'directory. (${!fileSameSize})');
      debugPrint('About to get byte data for $modelPath');

      List<int> bytes = assetByteData.buffer.asUint8List(
        assetByteData.offsetInBytes,
        assetByteData.lengthInBytes,
      );
      debugPrint('About to copy model to $modelPath');
      try {
        if (!fileExists) {
          await file.create(recursive: true);
        }
        await file.writeAsBytes(bytes, flush: true);
      } catch (e) {
        debugPrint('Error writing bytes to $modelPath: $e');
        rethrow;
      }
      debugPrint('Copied model to $modelPath');
    }

    return modelPath;
  }
}
