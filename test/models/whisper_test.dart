import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:fonnx/models/whisper/whisper.dart';
import 'package:fonnx/models/whisper/whisper_native.dart';

void main() {
  /// This is the smallest model I'm comfortable checking into Git, but
  /// whisper_small is the model I'd use in production: word error rate is
  /// too high for whisper_tiny and whisper_base. The size advantage isn't
  /// worth the accuracy loss, it's too frustrating to use.
  final whisper = WhisperNative(
    WhisperBundle.tiny('example/assets/models/whisper'),
  );

  test('Whisper works', () async {
    final bytes = await File(
      'test/data/audio_sample_ac1_ar16000.pcm',
    ).readAsBytes();
    final transcript = await whisper.doInference(bytes);
    expect(transcript, 'The rain in Spain falls mainly on the plane.');
  });

  test('Whisper keeps the first sentence when speech starts at 0 s', () async {
    // Greedy decoding starts this clip at "How are you doing?", the second
    // sentence. Beam search keeps the first one.
    final rain = await File(
      'test/data/audio_sample_ac1_ar16000.pcm',
    ).readAsBytes();
    final talk = await File('test/data/talkovergpt.pcm').readAsBytes();
    final clip = BytesBuilder(copy: false);
    for (var i = 0; i < 3; i++) {
      clip
        ..add(rain)
        ..add(talk);
    }
    final bytes = Uint8List.sublistView(clip.takeBytes(), 0, 28 * 32000);
    final transcript = await whisper.doInference(bytes);
    expect(transcript, startsWith('The rain in Spain falls mainly'));
    expect(transcript, contains('How are you doing?'));
  });

  test('Whisper transcribes a tongue twister', () async {
    final bytes = await File(
      'test/data/woodchuck_ac1_ar16000.pcm',
    ).readAsBytes();
    expect(
      await whisper.doInference(bytes),
      'How much wood could a wood chuck chuck if a wood chuck could chuck wood?',
    );
  });

  test('Whisper rejects more than 30 seconds of audio', () async {
    final bytes = Uint8List(30 * 32000 + 2);
    await expectLater(whisper.doInference(bytes), throwsArgumentError);
    // The isolate still works afterwards.
    expect(
      await whisper.doInference(
        await File('test/data/audio_sample_ac1_ar16000.pcm').readAsBytes(),
      ),
      'The rain in Spain falls mainly on the plane.',
    );
  });

  // Whisper base and small are not in Git. Set FONNX_WHISPER_DIR to a
  // directory with whisper_<size>_encoder.onnx and whisper_<size>_decoder.onnx.
  final largerDirectory = Platform.environment['FONNX_WHISPER_DIR'];
  for (final (name, bundle, expected) in [
    (
      'base',
      WhisperBundle.base,
      'The rain in Spain falls mainly on the plane.',
    ),
    (
      'small',
      WhisperBundle.small,
      'The rain in Spain falls mainly on the plane.',
    ),
  ]) {
    test('Whisper $name works', () async {
      final model = WhisperNative(bundle(largerDirectory!));
      final bytes = await File(
        'test/data/audio_sample_ac1_ar16000.pcm',
      ).readAsBytes();
      expect(await model.doInference(bytes), expected);
    }, skip: largerDirectory == null ? 'FONNX_WHISPER_DIR is not set' : false);
  }

  test('Whisper performance', () async {
    final bytes = await File(
      'test/data/audio_sample_ac1_ar16000.pcm',
    ).readAsBytes();
    const iterations = 3;
    final Stopwatch sw = Stopwatch();
    for (var i = 0; i < iterations; i++) {
      if (i == 1) {
        sw.start();
      }
      await whisper.doInference(bytes);
    }
    sw.stop();
    print('Whisper performance:');
    final average =
        sw.elapsedMilliseconds.toDouble() / (iterations - 1).toDouble();
    print('  Average: ${average.toStringAsFixed(0)} ms');
    print('  Total: ${sw.elapsedMilliseconds} ms');
    final fileDurationMs = bytes.length / 32;
    final speedMultiplier = fileDurationMs / average;
    print('  Speed multiplier: ${speedMultiplier.toStringAsFixed(2)}x');
  });
}
