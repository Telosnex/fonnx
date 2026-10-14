import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fonnx/models/nemoAsr/nemo_asr.dart';
import 'package:fonnx/runtime_models.dart';
import 'package:fonnx_example/padding.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart' as path_provider;

/// The model is 132 MB, too large to bundle with the example. The first run
/// downloads it from its pinned Hugging Face commit.
const _modelPath = 'nemoAsr/fastconformer_ctc_multilingual_int8.onnx';

class NemoAsrWidget extends StatefulWidget {
  const NemoAsrWidget({super.key});

  @override
  State<NemoAsrWidget> createState() => _NemoAsrWidgetState();
}

class _NemoAsrWidgetState extends State<NemoAsrWidget> {
  bool _running = false;
  String? _status;
  String? _transcript;
  String? _speedTestResult;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        heightPadding,
        Text(
          'NVIDIA FastConformer',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const Text(
          'A 132 MB model provides speech recognition in 10 languages: '
          'Belarusian, Croatian, English, French, German, Italian, Polish, '
          'Russian, Spanish and Ukrainian. By NVIDIA, CC-BY-4.0. The first '
          'run downloads the model.',
        ),
        heightPadding,
        Row(
          children: [
            ElevatedButton(
              onPressed: _running ? null : _runPerformanceTest,
              child: const Text('Test Speed'),
            ),
            widthPadding,
            if (_status != null)
              Text(_status!, style: Theme.of(context).textTheme.bodyMedium)
            else if (_speedTestResult != null)
              Text(
                '${_speedTestResult}x realtime',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
          ],
        ),
        if (_transcript != null) ...[heightPadding, Text('"$_transcript"')],
      ],
    );
  }

  void _runPerformanceTest() async {
    setState(() {
      _running = true;
      _status = 'Getting model…';
    });
    try {
      final modelPath = await _getModelPath(
        onProgress: (received, total) {
          if (total == null || total == 0) return;
          final percent = (100 * received / total).floor();
          setState(() => _status = 'Downloading model: $percent%');
        },
      );
      setState(() => _status = 'Transcribing…');
      final nemoAsr = NemoAsr.load(
        NemoAsrBundle.fastConformerCtcMultilingualFile(modelPath),
      );
      final (transcript, speed) = await testNemoAsrPerformance(nemoAsr);
      setState(() {
        _transcript = transcript;
        _speedTestResult = speed;
        _status = null;
      });
    } catch (e) {
      debugPrint('NemoAsr failed: $e');
      setState(() => _status = 'Error: $e');
    } finally {
      setState(() => _running = false);
    }
  }
}

/// Returns the transcript and the speed as a multiple of realtime.
Future<(String, String)> testNemoAsrPerformance(NemoAsr nemoAsr) async {
  // "The rain in Spain falls mainly on the plain": 16-bit PCM, mono, 16 kHz.
  final pcm = await rootBundle.load('assets/audio_sample_ac1_ar16000.pcm');
  final bytes = pcm.buffer.asUint8List(pcm.offsetInBytes, pcm.lengthInBytes);
  final audioMs = bytes.length / 2 / 16000 * 1000;

  // The first run includes loading the model, so it is not timed.
  const iterations = 3;
  var transcript = '';
  final sw = Stopwatch();
  for (var i = 0; i < iterations; i++) {
    if (i == 1) sw.start();
    transcript = await nemoAsr.doInference(bytes);
  }
  sw.stop();
  final average = sw.elapsedMilliseconds / (iterations - 1);
  final speed = audioMs / average;
  debugPrint('NemoAsr performance:');
  debugPrint('  Average: ${average.toStringAsFixed(0)} ms');
  debugPrint('  Speed multiplier: ${speed.toStringAsFixed(2)}x');
  debugPrint('  Transcript: $transcript');
  debugPrint('  Model: ${nemoAsr.bundle}');
  return (transcript, speed.toStringAsFixed(2));
}

/// On native platforms, downloads the model into the application support
/// directory once and verifies its SHA-256. On web, the model loads straight
/// from its pinned URL.
Future<String> _getModelPath({
  void Function(int received, int? total)? onProgress,
}) async {
  if (kIsWeb) {
    return nativePrebuiltRuntimeFiles[path.basename(_modelPath)]!.url;
  }
  final support = await path_provider.getApplicationSupportDirectory();
  final file = await ensureFonnxRuntimeModel(
    _modelPath,
    Directory(path.join(support.path, 'models')),
    onProgress: onProgress,
  );
  return file.path;
}
