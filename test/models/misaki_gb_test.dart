import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:fonnx/models/kokoro/misaki/misaki.dart';
import 'package:fonnx/models/kokoro/misaki/misaki_fallback_ffi.dart';
import 'package:fonnx/onnx/ort.dart';

void main() {
  test(
    'British English matches 1096 Python references with and without fallback',
    () {
      const dir = 'example/assets/models/kokoro';
      final session = createOrtSession('$dir/misaki/g2p_fallback_en_us.onnx');
      addTearDown(session.release);
      final fallback = MisakiFallbackFfi(
        session,
        File('$dir/misaki/g2p_fallback_en_us.json').readAsStringSync(),
      );
      final misaki = Misaki.load(
        gold: jsonDecode(File('$dir/misaki/gb_gold.json').readAsStringSync()),
        silver: jsonDecode(
          File('$dir/misaki/gb_silver.json').readAsStringSync(),
        ),
        spacyConfigJson: File(
          '$dir/spacy/en_core_web_sm.json',
        ).readAsStringSync(),
        spacyWeights: File(
          '$dir/spacy/en_core_web_sm_tagger.bin',
        ).readAsBytesSync(),
        british: true,
      );
      final withFallback = Misaki(
        spacy: misaki.spacy,
        g2p: MisakiG2P(lexicon: misaki.g2p.lexicon, fallback: fallback.call),
      );
      final golden =
          jsonDecode(
                File('test/data/goldens/misaki_en_gb.json').readAsStringSync(),
              )
              as List;
      final failures = <String>[];
      for (final g in golden) {
        final text = g['text'] as String;
        if (misaki.phonemize(text) != g['phonemes']) {
          failures.add(
            'No fallback: $text\n${misaki.phonemize(text)}\n${g['phonemes']}',
          );
        }
        if (withFallback.phonemize(text) != g['phonemes_fallback']) {
          failures.add(
            'Fallback: $text\n${withFallback.phonemize(text)}\n${g['phonemes_fallback']}',
          );
        }
      }
      expect(failures, isEmpty, reason: failures.take(10).join('\n'));
    },
  );
}
