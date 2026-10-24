import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:fonnx/models/kokoro/misaki/misaki.dart';
import 'package:fonnx/models/kokoro/misaki/misaki_fallback_ffi.dart';
import 'package:fonnx/onnx/ort.dart';
import 'package:fonnx/models/kokoro/misaki/num2words_en.dart';
import 'package:fonnx/models/kokoro/misaki/spacy_en.dart';

const _dicts = 'example/assets/models/kokoro/misaki';

MisakiLexicon loadLexicon() => MisakiLexicon(
  gold: jsonDecode(File('$_dicts/us_gold.json').readAsStringSync()),
  silver: jsonDecode(File('$_dicts/us_silver.json').readAsStringSync()),
);

void main() {
  final golden =
      (jsonDecode(
                File('test/data/goldens/misaki_en_us.json').readAsStringSync(),
              )
              as List)
          .cast<Map<String, dynamic>>();

  spacyAndEndToEnd(golden);
  endToEnd(golden);

  group('num2words', () {
    test('cardinal, ordinal, year, float', () {
      String c(int n) => num2wordsCardinal(BigInt.from(n));
      expect(c(0), 'zero');
      expect(c(21), 'twenty-one');
      expect(c(101), 'one hundred and one');
      expect(c(1984), 'one thousand, nine hundred and eighty-four');
      expect(c(7900000000), 'seven billion, nine hundred million');
      expect(
        c(123456789012),
        'one hundred and twenty-three billion, four hundred and fifty-six '
        'million, seven hundred and eighty-nine thousand and twelve',
      );
      expect(num2wordsOrdinal(BigInt.from(21)), 'twenty-first');
      expect(num2wordsOrdinal(BigInt.from(1001)), 'one thousand and first');
      expect(num2wordsOrdinal(BigInt.from(99)), 'ninety-ninth');
      expect(num2wordsYear(101), 'one oh-one');
      expect(num2wordsYear(1984), 'nineteen eighty-four');
      expect(num2wordsYear(2005), 'two thousand and five');
      expect(num2wordsYear(1000), 'one thousand');
      expect(num2wordsFloat(3.14159), 'three point one four one five nine');
      expect(num2wordsFloat(1.05), 'one point zero five');
      expect(
        num2wordsFloat(0.00001234),
        'zero point zero zero zero zero one two three four',
      );
      expect(num2wordsFloat(98.6), 'ninety-eight point six');
    });
  });

  test('misaki lexicon + pipeline matches Python on spaCy tokens', () {
    final sw = Stopwatch()..start();
    final g2p = MisakiG2P(lexicon: loadLexicon());
    // ignore: avoid_print
    print('lexicon load: ${sw.elapsedMilliseconds}ms');
    sw.reset();
    final failures = <String>[];
    for (final g in golden) {
      final pre = MisakiG2P.preprocess(g['text'] as String);
      final spacy = (g['spacy'] as List).cast<List>();
      final tokens = [
        for (final t in spacy)
          MToken(
            text: t[0] as String,
            tag: t[1] as String,
            whitespace: t[2] as String,
          ),
      ];
      MisakiG2P.applyFeatures(
        tokens,
        [for (final t in spacy) t[3] as int],
        pre.text,
        pre.tokens,
        pre.features,
      );
      final (ps, _) = g2p.phonemizeTokens(tokens);
      if (ps != g['phonemes']) {
        failures.add('${g['text']}\n  want: ${g['phonemes']}\n  got:  $ps');
      }
    }
    // ignore: avoid_print
    print(
      '${golden.length} sentences in ${sw.elapsedMilliseconds}ms, '
      '${failures.length} mismatches',
    );
    expect(failures, isEmpty, reason: failures.take(15).join('\n'));
  });
}

void spacyAndEndToEnd(List<Map<String, dynamic>> golden) {
  const dir = 'example/assets/models/kokoro/spacy';
  final spacy = SpacyEnglish.load(
    File('$dir/en_core_web_sm.json').readAsStringSync(),
    File('$dir/en_core_web_sm_tagger.bin').readAsBytesSync(),
  );

  test('spaCy tokenizer matches Python', () {
    final failures = <String>[];
    for (final g in golden) {
      final pre = MisakiG2P.preprocess(g['text'] as String);
      final want = [
        for (final t in (g['spacy'] as List).cast<List>())
          '${t[0]}|${t[2]}|${t[3]}',
      ];
      final got = [
        for (final t in spacy.tokenize(pre.text))
          '${t.text}|${t.whitespace}|${t.idx}',
      ];
      if (want.join('  ') != got.join('  ')) {
        failures.add('${g['text']}\n  want: $want\n  got:  $got');
      }
    }
    expect(failures, isEmpty, reason: failures.take(10).join('\n'));
  });

  test('spaCy tagger matches Python', () {
    var total = 0;
    final failures = <String>[];
    final sw = Stopwatch()..start();
    for (final g in golden) {
      final spacyTokens = (g['spacy'] as List).cast<List>();
      final doc = [
        for (final t in spacyTokens)
          SpacyToken(t[0] as String, spacy: (t[2] as String).isNotEmpty),
      ];
      // Special-case norms come from the tokenizer, so tag our own tokens.
      final pre = MisakiG2P.preprocess(g['text'] as String);
      final ours = spacy(pre.text);
      total += ours.length;
      for (var i = 0; i < ours.length && i < doc.length; i++) {
        if (ours[i].tag != spacyTokens[i][1]) {
          failures.add(
            '${g['text']}: ${ours[i].text} '
            'want ${spacyTokens[i][1]} got ${ours[i].tag}',
          );
        }
      }
    }
    // ignore: avoid_print
    print('tagged $total tokens in ${sw.elapsedMilliseconds}ms');
    expect(failures, isEmpty, reason: failures.take(15).join('\n'));
  });
}

void endToEnd(List<Map<String, dynamic>> golden) {
  test('Misaki end to end (text -> phonemes) matches Python', () {
    const dir = 'example/assets/models/kokoro';
    final sw = Stopwatch()..start();
    final misaki = Misaki.load(
      gold: jsonDecode(File('$dir/misaki/us_gold.json').readAsStringSync()),
      silver: jsonDecode(File('$dir/misaki/us_silver.json').readAsStringSync()),
      spacyConfigJson: File(
        '$dir/spacy/en_core_web_sm.json',
      ).readAsStringSync(),
      spacyWeights: File(
        '$dir/spacy/en_core_web_sm_tagger.bin',
      ).readAsBytesSync(),
    );
    // ignore: avoid_print
    print('Misaki.load: ${sw.elapsedMilliseconds}ms');
    // Warm up, then time one typical sentence.
    for (var i = 0; i < 20; i++) {
      misaki.phonemize(golden[i]['text'] as String);
    }
    sw.reset();
    const reps = 50;
    for (var i = 0; i < reps; i++) {
      misaki.phonemize(golden[1]['text'] as String);
    }
    // ignore: avoid_print
    print(
      '"${golden[1]['text']}": '
      '${(sw.elapsedMicroseconds / reps / 1000).toStringAsFixed(2)}ms',
    );
    final failures = <String>[];
    for (final g in golden) {
      final ps = misaki.phonemize(g['text'] as String);
      if (ps != g['phonemes']) {
        failures.add('${g['text']}\n  want: ${g['phonemes']}\n  got:  $ps');
      }
    }
    expect(failures, isEmpty, reason: failures.take(10).join('\n'));
  });

  test('Misaki with BART fallback matches Python (misaki main)', () {
    const dir = 'example/assets/models/kokoro';
    final session = createOrtSession('$dir/misaki/g2p_fallback_en_us.onnx');
    addTearDown(session.release);
    final fallback = MisakiFallbackFfi(
      session,
      File('$dir/misaki/g2p_fallback_en_us.json').readAsStringSync(),
    );
    final misaki = Misaki.load(
      gold: jsonDecode(File('$dir/misaki/us_gold.json').readAsStringSync()),
      silver: jsonDecode(File('$dir/misaki/us_silver.json').readAsStringSync()),
      spacyConfigJson: File(
        '$dir/spacy/en_core_web_sm.json',
      ).readAsStringSync(),
      spacyWeights: File(
        '$dir/spacy/en_core_web_sm_tagger.bin',
      ).readAsBytesSync(),
      fallback: fallback.call,
    );
    final sw = Stopwatch()..start();
    final failures = <String>[];
    for (final g in golden) {
      final ps = misaki.phonemize(g['text'] as String);
      if (ps != g['phonemes_fallback']) {
        failures.add(
          '${g['text']}\n  want: ${g['phonemes_fallback']}\n  got:  $ps',
        );
      }
    }
    // ignore: avoid_print
    print(
      '${golden.length} sentences with fallback: ${sw.elapsedMilliseconds}ms',
    );
    expect(failures, isEmpty, reason: failures.take(10).join('\n'));
  });
}
