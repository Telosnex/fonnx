import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fonnx/models/whisper/whisper_native.dart';

void main() {
  /// This is the smallest model I'm comfortable checking into Git, but
  /// whisper_small is the model I'd use in production: word error rate is
  /// too high for whisper_tiny and whisper_base. The size advantage isn't
  /// worth the accuracy loss, it's too frustrating to use.
  const modelPath = 'example/assets/models/whisper/whisper_tiny.onnx';
  final whisper = WhisperNative(modelPath);
  final shouldSkip = !Platform.isMacOS && !Platform.isLinux;
  final skipReason = shouldSkip
      ? 'Whisper only works on ARM64 Mac and X64 Linux currently'
      : null;

  test('Whisper works', skip: skipReason, () async {
    String testFilePath = 'test/data/rain_in_spain.wav';
    File file = File(testFilePath);
    final bytes = await file.readAsBytes();
    final transcript = await whisper.doInference(bytes);
    // whisper_tiny:
    expect(transcript.trim(), 'The rain and Spain falls mainly on the plane.');
    // whisper_base:
    //  expect(transcript.trim(), 'The rain in Spain falls, mainly on the plain.');
    // whisper_small:
    //    expect(transcript.trim(), 'The rain in Spain falls mainly on the plain.');
  });

  test('Whisper over 30 seconds does not work', skip: skipReason, () async {
    String testFilePath = 'test/data/1272-141231-0002x3.mp3';
    File file = File(testFilePath);
    try {
      final bytes = await file.readAsBytes();
      await whisper.doInference(bytes);
      fail('Should have thrown an exception');
    } catch (e) {
      expect(e, isA<Exception>());
    }
  });

  test('Whisper performance', skip: skipReason, () async {
    String testFilePath = 'test/data/rain_in_spain.wav';
    File file = File(testFilePath);
    final bytes = await file.readAsBytes();
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
  });
}
