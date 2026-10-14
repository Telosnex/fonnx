import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fonnx/extensions/uint8list.dart';
import 'package:fonnx/models/senseVoice/sense_voice.dart';
import 'package:fonnx/models/senseVoice/sense_voice_native.dart';
import 'package:fonnx/models/senseVoice/src/sense_voice_engine.dart';
import 'package:fonnx/models/senseVoice/src/sense_voice_features.dart';

const _rain = 'test/data/audio_sample_ac1_ar16000.pcm';

void main() {
  test('features match the reference', () async {
    // Values from a NumPy port that gave sherpa-onnx's transcripts. Its
    // filter bank matched kaldi-native-fbank to 2e-4.
    final samples = (await File(_rain).readAsBytes()).toAudioFloat32List();
    final frames = senseVoiceFrames(samples.length);
    expect(frames, 83);
    final features = senseVoiceFeatures(samples);
    expect(features.length, frames * senseVoiceFeatureWidth);
    for (final MapEntry(key: (t, c), :value) in {
      (0, 0): 0.3017,
      (10, 300): -0.6953,
      (82, 559): -0.6041,
    }.entries) {
      expect(features[t * senseVoiceFeatureWidth + c], closeTo(value, 1e-3));
    }
  });

  test('audio shorter than one frame has no features', () {
    expect(senseVoiceFrames(399), 0);
    expect(senseVoiceFrames(400), 1);
    expect(senseVoiceFrames(400 + 6 * 160), 2);
  });

  test('CTC drops repeats and blanks; text skips special tokens', () {
    const v = 4;
    final rows = [1, 1, 0, 1, 2, 2, 0, 3];
    final logits = Float32List(rows.length * v);
    for (var i = 0; i < rows.length; i++) {
      logits[i * v + rows[i]] = 1;
    }
    expect(greedySenseVoiceCtc(logits, v), [1, 1, 2, 3]);
    const vocabulary = ['<unk>', '▁Hal', 'lo', '<|en|>', '▁Welt'];
    expect(decodeSenseVoiceText(vocabulary, [3, 1, 2, 0, 4]), 'Hallo Welt');
  });

  test('tokens.txt parses by ID, with tokens that contain spaces', () {
    expect(parseSenseVoiceTokens('<unk> 0\n▁the 1\n▁ 2\n'), [
      '<unk>',
      '▁the',
      '▁',
    ]);
    expect(() => parseSenseVoiceTokens('a 0\nb 2\n'), throwsFormatException);
  });

  final senseVoice = SenseVoiceNative(
    SenseVoiceBundle.inDirectory('example/assets/models/senseVoice'),
  );

  test('English, detected', () async {
    expect(
      await senseVoice.doInference(await File(_rain).readAsBytes()),
      'The rain in Spain falls mainly on the plain.',
    );
  });

  test('English with the language set', () async {
    expect(
      await senseVoice.doInference(
        await File(_rain).readAsBytes(),
        language: SenseVoiceLanguage.english,
      ),
      'The rain in Spain falls mainly on the plain.',
    );
  });

  test('less than one frame gives no text', () async {
    expect(await senseVoice.doInference(Uint8List(100)), isEmpty);
  });

  test('silence gives a short false transcript, as in sherpa-onnx', () async {
    // The model, not this port: sherpa-onnx gives the same for silence and
    // quiet noise. Run a VAD first.
    expect(await senseVoice.doInference(Uint8List(32000)), '그。');
  });

  test('rejects more than 60 seconds of audio', () async {
    await expectLater(
      senseVoice.doInference(Uint8List(senseVoiceMaxSamples * 2 + 2)),
      throwsArgumentError,
    );
    expect(
      await senseVoice.doInference(await File(_rain).readAsBytes()),
      'The rain in Spain falls mainly on the plain.',
    );
  });

  test('performance', () async {
    final bytes = await File(_rain).readAsBytes();
    const iterations = 3;
    final sw = Stopwatch();
    for (var i = 0; i < iterations; i++) {
      if (i == 1) sw.start();
      await senseVoice.doInference(bytes);
    }
    sw.stop();
    final average = sw.elapsedMilliseconds / (iterations - 1);
    debugPrint('SenseVoice performance:');
    debugPrint('  Average: ${average.toStringAsFixed(0)} ms');
    debugPrint(
      '  Speed multiplier: '
      '${(bytes.length / 32 / math.max(average, 1)).toStringAsFixed(2)}x',
    );
  });
}
