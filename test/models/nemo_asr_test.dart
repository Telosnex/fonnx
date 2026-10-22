import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fonnx/extensions/uint8list.dart';
import 'package:fonnx/models/nemoAsr/nemo_asr.dart';
import 'package:fonnx/models/nemoAsr/nemo_asr_native.dart';
import 'package:fonnx/models/nemoAsr/src/nemo_asr_engine.dart';
import 'package:fonnx/models/nemoAsr/src/nemo_asr_features.dart';
import 'package:fonnx/models/nemoAsr/src/nemo_asr_vocabulary.dart';

const _rain = 'test/data/audio_sample_ac1_ar16000.pcm';
const _woodchuck = 'test/data/woodchuck_ac1_ar16000.pcm';
const _beijing = 'test/data/what_time_is_it_in_beijing_ac1_ar16000.pcm';

void main() {
  group('features', () {
    // Values from a NumPy port of NeMo's preprocessor that gave the same
    // transcripts as sherpa-onnx on 360 FLEURS sentences.
    for (final (bins, expected) in [
      (80, {(0, 0): -0.5428, (40, 100): 0.4414, (79, 494): -0.7062}),
      (128, {(0, 0): -0.0788, (64, 100): 0.3311, (127, 494): -0.6552}),
    ]) {
      test('$bins mel bins match the reference', () async {
        final samples = (await File(_rain).readAsBytes()).toAudioFloat32List();
        final frames = nemoAsrFrames(samples.length);
        expect(frames, 495);
        final features = nemoAsrLogMel(samples, bins);
        expect(features.length, bins * frames);
        for (final MapEntry(key: (mel, t), :value) in expected.entries) {
          expect(features[mel * frames + t], closeTo(value, 1e-3));
        }
      });
    }
  });

  group('lead-in', () {
    test('adds silence before speech at the first sample', () {
      final loud = Float32List(1000)..fillRange(0, 1000, 0.5);
      final padded = withNemoAsrLeadIn(loud);
      expect(padded.length, nemoAsrLeadInSamples + 1000);
      expect(padded.take(nemoAsrLeadInSamples).every((v) => v == 0), isTrue);
    });

    test('adds only the missing part of the quiet', () {
      final samples = Float32List(nemoAsrLeadInSamples)
        ..fillRange(1600, nemoAsrLeadInSamples, 0.5);
      expect(
        withNemoAsrLeadIn(samples).length,
        2 * nemoAsrLeadInSamples - 1600,
      );
    });

    test('keeps audio that starts with quiet', () {
      final samples = Float32List(nemoAsrLeadInSamples + 10)
        ..fillRange(nemoAsrLeadInSamples, nemoAsrLeadInSamples + 10, 0.5);
      expect(identical(withNemoAsrLeadIn(samples), samples), isTrue);
    });
  });

  group('decoding', () {
    test('CTC drops repeats and blanks', () {
      const v = 4;
      final rows = [1, 1, 3, 1, 2, 2, 3, 3, 0];
      final logits = Float32List(rows.length * v);
      for (var i = 0; i < rows.length; i++) {
        logits[i * v + rows[i]] = 1;
      }
      expect(greedyCtc(logits, v), [1, 1, 2, 0]);
    });

    test('text joins word pieces and skips special tokens', () {
      const vocabulary = ['<unk>', '▁Hal', 'lo', '▁Welt', '<blk>'];
      expect(decodeNemoAsrText(vocabulary, [1, 2, 0, 3]), 'Hallo Welt');
    });

    test('TDT follows durations and limits tokens per frame', () async {
      final blank = parakeetTdtV3Blank;
      // Frame 0: one token, duration 0, then six more tokens with duration 0,
      // so the limit moves to frame 1. Frame 1: blank, duration 2.
      final backend = _FakeTdtBackend(
        frames: 3,
        script: {
          0: [for (var i = 0; i < 7; i++) (10 + i, 0)],
          1: [(blank, 2)],
        },
      );
      final engine = NemoAsrEngine(backend, NemoAsrModel.parakeetTdtV3);
      final tokens = await engine.transcribeTokens(Float32List(1600));
      expect(tokens, [10, 11, 12, 13, 14]);
      expect(backend.jointFrames, [0, 0, 0, 0, 0, 1]);
      expect(backend.predicted, [10, 11, 12, 13, 14]);
    });
  });

  final ctc = NemoAsrNative(
    NemoAsrBundle.fastConformerCtcMultilingual('example/assets/models/nemoAsr'),
  );

  test('FastConformer CTC works', () async {
    final bytes = await File(_rain).readAsBytes();
    expect(
      await ctc.doInference(bytes),
      'The rain in Spain falls mainly on the plain.',
    );
  });

  test('FastConformer CTC transcribes Spanish', () async {
    // English, then Spanish: "Estoy bien, gracias, ¿y tú cómo estás?".
    final transcript = await ctc.doInference(
      await File('test/data/talkovergpt.pcm').readAsBytes(),
    );
    expect(transcript, contains('are you doing'));
    expect(transcript, contains('como'));
  });

  test('FastConformer CTC transcribes a short question', () async {
    expect(
      await ctc.doInference(await File(_beijing).readAsBytes()),
      'What time is it in Beijing?',
    );
  });

  test('NemoAsr rejects more than 60 seconds of audio', () async {
    await expectLater(
      ctc.doInference(Uint8List(nemoAsrMaxSamples * 2 + 2)),
      throwsArgumentError,
    );
    // The isolate still works afterwards.
    expect(
      await ctc.doInference(await File(_rain).readAsBytes()),
      'The rain in Spain falls mainly on the plain.',
    );
  });

  test('Parakeet TDT v3 works', () async {
    final v3 = NemoAsrNative(
      NemoAsrBundle.parakeetTdtV3('example/assets/models/nemoAsr'),
    );
    expect(
      await v3.doInference(await File(_rain).readAsBytes()),
      'The rain in Spain falls mainly on the plane.',
    );
    // The first run gives only blanks; the run with more silence before the
    // speech does not.
    expect(
      await v3.doInference(
        await File('test/data/talkovergpt.pcm').readAsBytes(),
      ),
      'Estoy bien, gracias.',
    );
    expect(
      await v3.doInference(await File(_woodchuck).readAsBytes()),
      'How much wood could a woodchuck chuck if a woodchuck could chuck wood?',
    );
  });

  test('FastConformer CTC performance', () async {
    final bytes = await File(_rain).readAsBytes();
    const iterations = 3;
    final sw = Stopwatch();
    for (var i = 0; i < iterations; i++) {
      if (i == 1) sw.start();
      await ctc.doInference(bytes);
    }
    sw.stop();
    final average = sw.elapsedMilliseconds / (iterations - 1);
    debugPrint('FastConformer CTC performance:');
    debugPrint('  Average: ${average.toStringAsFixed(0)} ms');
    debugPrint(
      '  Speed multiplier: '
      '${(bytes.length / 32 / math.max(average, 1)).toStringAsFixed(2)}x',
    );
  });
}

final class _FakeTdtBackend implements NemoAsrOnnxBackend {
  _FakeTdtBackend({required this.frames, required this.script});

  final int frames;

  /// For each frame, the (token, duration) of each joiner call in turn.
  final Map<int, List<(int, int)>> script;
  final jointFrames = <int>[];
  final predicted = <int>[];
  final _calls = <int, int>{};

  @override
  Future<Float32List> encode(Float32List features, int frames) async =>
      Float32List.fromList([this.frames.toDouble()]);

  @override
  Future<Float32List> joint(int frame) async {
    jointFrames.add(frame);
    final call = _calls[frame] = (_calls[frame] ?? -1) + 1;
    final steps = script[frame] ?? const [];
    final (token, duration) = call < steps.length
        ? steps[call]
        : (parakeetTdtV3Blank, 1);
    final logits = Float32List(parakeetTdtV3Tokens.length + 5);
    logits[token] = 1;
    logits[parakeetTdtV3Tokens.length + duration] = 1;
    return logits;
  }

  @override
  Future<void> predict(int token) async => predicted.add(token);

  @override
  Future<void> close() async {}
}
