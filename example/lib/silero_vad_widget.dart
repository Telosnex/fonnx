import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fonnx/models/sileroVad/silero_vad.dart';
import 'package:fonnx_example/padding.dart';
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
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        heightPadding,
        Text(
          'Silero VAD',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const Text(
            '1 MB model detects when speech is present in audio. By Silero.'),
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
    final modelPath = await getModelPath('silero_vad.onnx');
    final silero = SileroVad.load(modelPath);
    final wavFile = await rootBundle.load('assets/audio_sample_16khz.wav');
    final result = await silero.doInference(wavFile.buffer.asUint8List());
    setState(() {
      // obtained on macOS M2 9 Feb 2024.
      final acceptableAnswers = {
        0.4739372134208679, // macOS MBP M2 10 Feb 2024
        0.4739373028278351, // Android Pixel Fold 10 Feb 2024
        0.4739360809326172, // Web 15 Feb 2024
      };
      _verifyPassed = result.length == 3 &&
          acceptableAnswers.contains(result['output'].first);
      if (_verifyPassed != true) {
        if (kDebugMode) {
          print(
              'verification of Silero output failed, got ${result['output']}');
        }
      }
    });
  }

  void _runPerformanceTest() async {
    final modelPath = await getModelPath('silero_vad.onnx');
    final sileroVad = SileroVad.load(modelPath);
    final result = await testPerformance(sileroVad);
    setState(() {
      _speedTestResult = result;
    });
  }

  static Future<String> testPerformance(SileroVad sileroVad) async {
    final vadPerfWavFile =
        await rootBundle.load('assets/audio_sample_16khz.wav');
    final bytes = vadPerfWavFile.buffer.asUint8List();
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
