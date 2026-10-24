import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:fonnx/models/kokoro/kokoro.dart';
import 'package:fonnx/models/kokoro/kokoro_chunking.dart';
import 'package:fonnx/models/kokoro/kokoro_normalizer.dart';
import 'package:fonnx/models/kokoro/misaki/misaki.dart';
import 'package:fonnx/models/kokoro/misaki/misaki_fallback_ffi.dart';
import 'package:fonnx/onnx/ort.dart';

import 'kokoro_web_golden.dart';

/// Checks the native engine against test/data/goldens/kokoro_web.json, which
/// test/models/kokoro_web_test.dart checks web against. The phonemes come
/// from misaki with its synchronous fallback, so this also checks that the
/// engine's asynchronous fallback gives the same phonemes.
///
/// Write the golden again with --dart-define=KOKORO_WRITE_WEB_GOLDEN=true.
void main() {
  const dir = 'example/assets/models/kokoro';
  const golden = 'test/data/goldens/kokoro_web.json';
  const write = bool.fromEnvironment('KOKORO_WRITE_WEB_GOLDEN');

  test('native Kokoro matches the web golden', () async {
    final fallbackSession = createOrtSession(
      '$dir/misaki/g2p_fallback_en_us.onnx',
    );
    addTearDown(fallbackSession.release);
    final fallback = MisakiFallbackFfi(
      fallbackSession,
      File('$dir/misaki/g2p_fallback_en_us.json').readAsStringSync(),
    );
    Map<String, dynamic> json(String f) =>
        jsonDecode(File('$dir/misaki/$f').readAsStringSync())
            as Map<String, dynamic>;
    final us = Misaki.load(
      gold: json('us_gold.json'),
      silver: json('us_silver.json'),
      spacyConfigJson: File(
        '$dir/spacy/en_core_web_sm.json',
      ).readAsStringSync(),
      spacyWeights: File(
        '$dir/spacy/en_core_web_sm_tagger.bin',
      ).readAsBytesSync(),
      fallback: fallback.call,
      unk: '',
    );
    final gb = Misaki(
      spacy: us.spacy,
      g2p: MisakiG2P(
        lexicon: MisakiLexicon(
          gold: json('gb_gold.json'),
          silver: json('gb_silver.json'),
          british: true,
        ),
        fallback: fallback.call,
        unk: '',
      ),
    );
    final engine = await Kokoro.load(
      KokoroBundle.fromDirectory(dir),
      policy: kokoroWebPolicy,
    );
    addTearDown(engine.dispose);

    final cases = <Map<String, Object?>>[];
    for (final c in kokoroWebCases) {
      final misaki = c.voice.startsWith('a') ? us : gb;
      final phonemes = kokoroSplitPhonemes(
        misaki.phonemize(normalizeKokoroEnglish(c.text)),
      ).join(' ');
      final chunks = await engine.speak(c.text, voice: c.voice).toList();
      expect(chunks.first.phonemes, phonemes, reason: c.text);
      final audio = Float32List.fromList([
        for (final chunk in chunks) ...chunk.samples,
      ]);
      cases.add({
        'voice': c.voice,
        'text': c.text,
        'phonemes': phonemes,
        'samples': audio.length,
        'envelope': [
          for (final v in kokoroEnvelope(audio))
            double.parse(v.toStringAsFixed(5)),
        ],
      });
    }
    if (write) {
      File(golden).writeAsStringSync(
        '${const JsonEncoder.withIndent(' ').convert(cases)}\n',
      );
      return;
    }
    final want = (jsonDecode(File(golden).readAsStringSync()) as List)
        .cast<Map<String, dynamic>>();
    for (var i = 0; i < want.length; i++) {
      expect(cases[i]['phonemes'], want[i]['phonemes']);
      expect(cases[i]['samples'], want[i]['samples']);
    }
  });
}
