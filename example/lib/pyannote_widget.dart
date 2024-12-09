import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fonnx/models/pyannote/pyannote.dart';
import 'package:fonnx_example/padding.dart';
import 'dart:async';
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:path/path.dart' as path;

class PyannoteWidget extends StatefulWidget {
  const PyannoteWidget({super.key});

  @override
  State<PyannoteWidget> createState() => _PyannoteWidgetState();
}

class _PyannoteWidgetState extends State<PyannoteWidget> {
  bool? _verifyPassed;
  String? _speedTestResult;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        heightPadding,
        Text(
          'Pyannote Speaker Diarization',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const Text(
            'Speaker diarization model that identifies who speaks when in audio.'),
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
      ],
    );
  }

  void _runVerificationTest() async {
    final modelPath = await getModelPath('pyannote_seg3.onnx');
    final pyannote = Pyannote.load(modelPath);

    // Get test audio file as Float32List
    final wavFile =
        await rootBundle.load('assets/audio_sample_ac1_ar16000.pcm');
    print('wavfile size: ${wavFile.buffer.asUint8List().length}');
    final processed =
        Pyannote.int16PcmBytesToFloat32(wavFile.buffer.asUint8List());
    final result = await pyannote.process(processed);
    setState(() {
      // Verify the basic structure and content of the result
      final isValidStructure = result.every((segment) =>
          segment.containsKey('speaker') &&
          segment.containsKey('start') &&
          segment.containsKey('stop'));

      // Verify the expected number of speakers and timing range
      final speakers = result.map((s) => s['speaker'] as int).toSet();
      final hasValidSpeakers =
          speakers.length <= 3 && speakers.every((s) => s >= 0 && s < 3);

      // Verify timing sequence
      var isValidTiming = true;
      double lastStop = 0;
      for (final segment in result) {
        final start = segment['start'] as double;
        final stop = segment['stop'] as double;
        if (start > stop || start < lastStop) {
          isValidTiming = false;
          break;
        }
        lastStop = stop;
      }
      
      final golden = kIsWeb
          ? [
              {"speaker": 1, "start": 0.8044375, "stop": 4.4494375}
            ]
          : [
              {'start': 0.8381875, 'speaker': 1, 'stop': 4.4831875}
            ];
      final matchesGolden = result.length == 1 &&
          result[0]['speaker'] == golden[0]['speaker'] &&
          result[0]['start'] == golden[0]['start'] &&
          result[0]['stop'] == golden[0]['stop'];
      _verifyPassed = isValidStructure &&
          hasValidSpeakers &&
          isValidTiming &&
          matchesGolden;

      if (_verifyPassed != true) {
        if (kDebugMode) {
          print('Verification of Pyannote output failed:');
          print('Structure valid: $isValidStructure');
          print('Speakers valid: $hasValidSpeakers');
          print('Timing valid: $isValidTiming');
          print('Result: $result');
        }
      }
    });
  }

  void _runPerformanceTest() async {
    final modelPath = await getModelPath('pyannote_seg3.onnx');
    final pyannote = Pyannote.load(modelPath);
    final result = await testPerformance(pyannote);
    setState(() {
      _speedTestResult = result;
    });
  }

  Future<String> testPerformance(Pyannote pyannote) async {
    // Get test audio file as Float32List
    final wavFile =
        await rootBundle.load('assets/audio_sample_ac1_ar16000.pcm');
    final audioData = wavFile.buffer.asFloat32List();

    const iterations = 3;
    final Stopwatch sw = Stopwatch();

    for (var i = 0; i < iterations; i++) {
      if (i == 1) {
        sw.start();
      }
      await pyannote.process(audioData);
    }
    sw.stop();

    debugPrint('Pyannote performance:');
    final average =
        sw.elapsedMilliseconds.toDouble() / (iterations - 1).toDouble();
    debugPrint('  Average: ${average.toStringAsFixed(0)} ms');
    debugPrint('  Total: ${sw.elapsedMilliseconds} ms');

    // Assuming test file is 10 seconds long
    const fileDurationMs = 10000;
    final speedMultiplier = fileDurationMs.toDouble() / average;
    debugPrint('  Speed multiplier: ${speedMultiplier.toStringAsFixed(2)}x');
    debugPrint('  Model path: ${pyannote.modelPath}');

    return speedMultiplier.toStringAsFixed(2);
  }

  Future<String> getModelPath(String modelFilenameWithExtension) async {
    if (kIsWeb) {
      return 'assets/models/pyannote/$modelFilenameWithExtension';
    }

    final assetCacheDirectory =
        await path_provider.getApplicationSupportDirectory();
    final modelPath =
        path.join(assetCacheDirectory.path, modelFilenameWithExtension);

    File file = File(modelPath);
    bool fileExists = await file.exists();
    final fileLength = fileExists ? await file.length() : 0;

    final assetPath =
        'assets/models/pyannote/${path.basename(modelFilenameWithExtension)}';
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
