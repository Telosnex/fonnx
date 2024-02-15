import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fonnx/models/whisper/whisper.dart';
import 'package:fonnx_example/padding.dart';
import 'dart:async';
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:path/path.dart' as path;

class WhisperWidget extends StatefulWidget {
  const WhisperWidget({super.key});

  @override
  State<WhisperWidget> createState() => _WhisperWidgetState();
}

class _WhisperWidgetState extends State<WhisperWidget> {
  bool? _verifyPassed;
  String? _speedTestResult;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        heightPadding,
        Text(
          'Whisper',
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
        )
      ],
    );
  }

  void _runVerificationTest() async {
    final modelPath =
        await getWhisperModelPath('whisper_tiny.onnx');
    final whisper = Whisper.load(modelPath);
    final pcmFile =
        await rootBundle.load('assets/audio_sample_ac1_ar16000.pcm');
    final result = await whisper.doInference(pcmFile.buffer.asUint8List());
    setState(() {
      _verifyPassed =
          result.trim() == 'The rain and Spain falls mainly on the plane.';
    });
  }

  void _runPerformanceTest() async {
    final modelPath =
        await getWhisperModelPath('whisper_tiny.onnx');
    final whisper = Whisper.load(modelPath);
    final result = await testPerformance(whisper);
    setState(() {
      _speedTestResult = result;
    });
  }

  static Future<String> testPerformance(Whisper whisper) async {
    final wavFile = await rootBundle.load('assets/audio_sample.wav');
    final bytes = wavFile.buffer.asUint8List();
    const iterations = 3;
    final Stopwatch sw = Stopwatch();
    for (var i = 0; i < iterations; i++) {
      if (i == 1) {
        sw.start();
      }
      await whisper.doInference(bytes);
    }
    sw.stop();
    debugPrint('Whisper performance:');
    final average =
        sw.elapsedMilliseconds.toDouble() / (iterations - 1).toDouble();
    debugPrint('  Average: ${average.toStringAsFixed(0)} ms');
    debugPrint('  Total: ${sw.elapsedMilliseconds} ms');
    const fileDurationMs = 5000;
    final speedMultilper = fileDurationMs.toDouble() / average;
    debugPrint('  Speed multiplier: ${speedMultilper.toStringAsFixed(2)}x');
    debugPrint('  Model path: ${whisper.modelPath}');
    return speedMultilper.toStringAsFixed(2);
  }

}



  Future<String> getWhisperModelPath(String modelFilenameWithExtension) async {
    if (kIsWeb) {
      return 'assets/models/whisper/$modelFilenameWithExtension';
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
        'assets/models/whisper/${path.basename(modelFilenameWithExtension)}';
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