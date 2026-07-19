// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fonnx/models/magika/magika.dart';
import 'package:fonnx/models/magika/magika_native.dart';
import 'package:fonnx/models/minilml6v2/mini_lm_l6_v2.dart';
import 'package:fonnx/models/minilml6v2/mini_lm_l6_v2_native.dart';
import 'package:fonnx/models/minishLab/minish_lab.dart';
import 'package:fonnx/models/minishLab/minish_lab_native.dart';
import 'package:fonnx/models/msmarcoMiniLmL6V3/msmarco_mini_lm_l6_v3.dart';
import 'package:fonnx/models/msmarcoMiniLmL6V3/msmarco_mini_lm_l6_v3_native.dart';
import 'package:fonnx/models/pyannote/pyannote.dart';
import 'package:fonnx/models/pyannote/pyannote_native.dart';
import 'package:fonnx/models/sileroVad/silero_vad_native.dart';
import 'package:fonnx/models/whisper/whisper_native.dart';

void main() {
  test(
    'Magika repeated inference RSS smoke test',
    () async {
      const modelPath = 'example/assets/models/magika/magika.onnx';
      final bytes =
          extractFeaturesFromBytes(
            await File('test/data/magika/basic/code.py').readAsBytes(),
          ).all;
      final magika = MagikaNative(modelPath);

      await _runRssSmoke(
        label: 'Magika',
        warmupIterations: 5,
        measuredIterations: 200,
        maxRssGrowthBytes: 30 * 1024 * 1024,
        body: (_) => magika.getType(bytes),
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'MiniLM repeated inference RSS smoke test',
    () async {
      const modelPath = 'example/assets/models/miniLmL6V2/miniLmL6V2.onnx';
      final miniLm = MiniLmL6V2Native(modelPath);
      final tokens =
          MiniLmL6V2.tokenizer
              .tokenize('This is a memory smoke test for native ORT cleanup.')
              .first
              .tokens;

      await _runRssSmoke(
        label: 'MiniLM',
        warmupIterations: 5,
        measuredIterations: 200,
        maxRssGrowthBytes: 30 * 1024 * 1024,
        body: (_) => miniLm.getEmbedding(tokens),
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
  test(
    'MS MARCO MiniLM repeated inference RSS smoke test',
    () async {
      const modelPath =
          'example/assets/models/msmarcoMiniLmL6V3/msmarcoMiniLmL6V3.onnx';
      final miniLm = MsmarcoMiniLmL6V3Native(modelPath);
      final tokens =
          MsmarcoMiniLmL6V3.tokenizer
              .tokenize('This is a memory smoke test for native ORT cleanup.')
              .first
              .tokens;

      await _runRssSmoke(
        label: 'MS MARCO MiniLM',
        warmupIterations: 5,
        measuredIterations: 200,
        maxRssGrowthBytes: 30 * 1024 * 1024,
        body: (_) => miniLm.getEmbedding(tokens),
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'MinishLab Potion 8M repeated inference RSS smoke test',
    () async {
      const modelPath = 'example/assets/models/minishLab/potion8m.onnx';
      final minishLab = MinishLabNative(modelPath);
      final tokens =
          MinishLab.potion8mTokenizer
              .tokenize('This is a memory smoke test for native ORT cleanup.')
              .first
              .tokens;

      await _runRssSmoke(
        label: 'MinishLab Potion 8M',
        warmupIterations: 5,
        measuredIterations: 200,
        maxRssGrowthBytes: 30 * 1024 * 1024,
        body: (_) => minishLab.getEmbedding(tokens),
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'MinishLab Potion 32M repeated inference RSS smoke test',
    () async {
      const modelPath = 'example/assets/models/minishLab/potion32m.onnx';
      final minishLab = MinishLabNative(modelPath);
      final tokens =
          MinishLab.potion32mTokenizer
              .tokenize('This is a memory smoke test for native ORT cleanup.')
              .first
              .tokens;

      await _runRssSmoke(
        label: 'MinishLab Potion 32M',
        warmupIterations: 5,
        measuredIterations: 200,
        maxRssGrowthBytes: 30 * 1024 * 1024,
        body: (_) => minishLab.getEmbedding(tokens),
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'Pyannote repeated inference RSS smoke test',
    () async {
      const modelPath = 'example/assets/models/pyannote/pyannote_seg3.onnx';
      final bytes =
          await File('test/data/audio_sample_ac1_ar16000.pcm').readAsBytes();
      final audioData = Pyannote.int16PcmBytesToFloat32(bytes);
      final pyannote = PyannoteNative(modelPath);

      await _runRssSmoke(
        label: 'Pyannote',
        warmupIterations: 2,
        measuredIterations: 40,
        maxRssGrowthBytes: 30 * 1024 * 1024,
        sampleEvery: 5,
        body: (_) => pyannote.process(audioData),
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'Whisper repeated inference RSS smoke test',
    skip:
        !Platform.isMacOS && !Platform.isLinux
            ? 'Whisper only works on ARM64 Mac and X64 Linux currently'
            : null,
    () async {
      const modelPath = 'example/assets/models/whisper/whisper_tiny.onnx';
      final bytes =
          await File('test/data/audio_sample_ac1_ar16000.pcm').readAsBytes();
      final whisper = WhisperNative(modelPath);

      await _runRssSmoke(
        label: 'Whisper',
        warmupIterations: 1,
        measuredIterations: 5,
        maxRssGrowthBytes: 30 * 1024 * 1024,
        sampleEvery: 1,
        body: (_) => whisper.doInference(bytes),
      );
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );

  test(
    'Silero VAD repeated inference RSS smoke test',
    () async {
      const modelPath =
          'example/assets/models/sileroVad/silero_vad_v6.2.1.onnx';
      final bytes =
          await File('test/data/audio_sample_ac1_ar16000.pcm').readAsBytes();
      final vad = SileroVadNative(modelPath);

      const warmupIterations = 5;
      const measuredIterations = 200;
      Map<String, dynamic> state = {};

      for (var i = 0; i < warmupIterations; i++) {
        state = await vad.doInference(bytes, previousState: state);
      }

      await Future<void>.delayed(const Duration(milliseconds: 100));
      final before = ProcessInfo.currentRss;
      print('Silero VAD RSS before: ${_formatBytes(before)}');

      for (var i = 0; i < measuredIterations; i++) {
        state = await vad.doInference(bytes, previousState: state);
        final iteration = i + 1;
        if (iteration % 25 == 0) {
          final current = ProcessInfo.currentRss;
          print(
            'Silero VAD RSS after $iteration iterations: '
            '${_formatBytes(current)} '
            '(delta ${_formatBytes(current - before)})',
          );
        }
      }

      await Future<void>.delayed(const Duration(milliseconds: 100));
      final after = ProcessInfo.currentRss;
      final delta = after - before;
      print('Silero VAD RSS after: ${_formatBytes(after)}');
      print('Silero VAD RSS delta: ${_formatBytes(delta)}');

      expect(state['output'], isA<Float32List>());
      expect(
        delta,
        lessThan(40 * 1024 * 1024),
        reason:
            'RSS grew by ${_formatBytes(delta)} after '
            '$measuredIterations repeated inferences.',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

Future<void> _runRssSmoke({
  required String label,
  required int warmupIterations,
  required int measuredIterations,
  required int maxRssGrowthBytes,
  required Future<Object?> Function(int iteration) body,
  int sampleEvery = 25,
}) async {
  Object? lastResult;
  for (var i = 0; i < warmupIterations; i++) {
    lastResult = await body(i);
  }

  await Future<void>.delayed(const Duration(milliseconds: 100));
  final before = ProcessInfo.currentRss;
  print('$label RSS before: ${_formatBytes(before)}');

  for (var i = 0; i < measuredIterations; i++) {
    lastResult = await body(i);
    final iteration = i + 1;
    if (iteration % sampleEvery == 0 || iteration == measuredIterations) {
      final current = ProcessInfo.currentRss;
      print(
        '$label RSS after $iteration iterations: '
        '${_formatBytes(current)} '
        '(delta ${_formatBytes(current - before)})',
      );
    }
  }

  await Future<void>.delayed(const Duration(milliseconds: 100));
  final after = ProcessInfo.currentRss;
  final delta = after - before;
  print('$label RSS after: ${_formatBytes(after)}');
  print('$label RSS delta: ${_formatBytes(delta)}');

  expect(lastResult, isNotNull);
  expect(
    delta,
    lessThan(maxRssGrowthBytes),
    reason:
        '$label RSS grew by ${_formatBytes(delta)} after '
        '$measuredIterations repeated inferences.',
  );
}

String _formatBytes(int bytes) {
  final sign = bytes < 0 ? '-' : '';
  final absoluteBytes = bytes.abs();
  final mib = absoluteBytes / (1024 * 1024);
  return '$sign${mib.toStringAsFixed(2)} MiB';
}
