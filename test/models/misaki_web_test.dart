@TestOn('browser')
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:fonnx/models/kokoro/misaki/misaki.dart';
import 'package:fonnx/models/kokoro/misaki/spacy_en.dart';

import 'spacy_hash_refs.dart';

/// Runs the spaCy and Misaki golden checks in the browser, where Dart ints
/// are JavaScript numbers (ADR 002 I2).
///
/// The test server serves test/ at the root, so the data comes from the
/// test/web_models link to example/assets/models. Build it first with
/// tool/kokoro/prepare_bundle.dart.
///
///   dart test -p chrome test/models/misaki_web_test.dart
void main() {
  const dir = '/web_models/kokoro';
  late SpacyEnglish spacy;
  late List<Map<String, dynamic>> usGolden, gbGolden;
  // Debug-compiled JavaScript runs the tagger slowly; every 10th sentence
  // keeps the run short. The VM tests check every sentence.
  List<Map<String, dynamic>> sample(List<Map<String, dynamic>> all) => [
    for (var i = 0; i < all.length; i += 10) all[i],
  ];

  setUpAll(() async {
    spacy = SpacyEnglish.load(
      await _text('$dir/spacy/en_core_web_sm.json'),
      await _bytes('$dir/spacy/en_core_web_sm_tagger.bin'),
    );
    usGolden = await _golden('/data/goldens/misaki_en_us.json');
    gbGolden = await _golden('/data/goldens/misaki_en_gb.json');
  });

  test('string ids match the 64-bit references', () {
    for (final MapEntry(:key, :value) in murmurRefs.entries) {
      expect(spacy.stringId(key).hex, value, reason: key);
    }
  });

  test('spaCy tokenizer and tagger match Python', () {
    final failures = <String>[];
    final sw = Stopwatch()..start();
    final checked = sample(usGolden);
    for (final g in checked) {
      final pre = MisakiG2P.preprocess(g['text'] as String);
      final want = [
        for (final t in (g['spacy'] as List).cast<List>())
          '${t[0]}|${t[1]}|${t[2]}|${t[3]}',
      ];
      final got = [
        for (final t in spacy(pre.text))
          '${t.text}|${t.tag}|${t.whitespace}|${t.idx}',
      ];
      if (want.join('  ') != got.join('  ')) {
        failures.add('${g['text']}\n  want: $want\n  got:  $got');
      }
    }
    // ignore: avoid_print
    print('tagged ${checked.length} sentences in ${sw.elapsedMilliseconds} ms');
    expect(failures, isEmpty, reason: failures.take(5).join('\n'));
  });

  for (final british in [false, true]) {
    test('Misaki ${british ? 'en-GB' : 'en-US'} matches Python', () async {
      final prefix = british ? 'gb' : 'us';
      final misaki = Misaki(
        spacy: spacy,
        g2p: MisakiG2P(
          lexicon: MisakiLexicon(
            gold: jsonDecode(await _text('$dir/misaki/${prefix}_gold.json')),
            silver: jsonDecode(
              await _text('$dir/misaki/${prefix}_silver.json'),
            ),
            british: british,
          ),
        ),
      );
      final failures = <String>[];
      for (final g in sample(british ? gbGolden : usGolden)) {
        final ps = misaki.phonemize(g['text'] as String);
        if (ps != g['phonemes']) {
          failures.add('${g['text']}\n  want: ${g['phonemes']}\n  got:  $ps');
        }
      }
      expect(failures, isEmpty, reason: failures.take(5).join('\n'));
    });
  }
}

Future<List<Map<String, dynamic>>> _golden(String path) async =>
    (jsonDecode(await _text(path)) as List).cast<Map<String, dynamic>>();

Future<String> _text(String path) async => utf8.decode(await _bytes(path));

Future<Uint8List> _bytes(String path) async {
  final response = await _fetch(path.toJS).toDart;
  if (!response.ok) fail('GET $path: HTTP ${response.status}');
  return (await response.arrayBuffer().toDart).toDart.asUint8List();
}

@JS('fetch')
external JSPromise<_Response> _fetch(JSString url);

extension type _Response(JSObject _) implements JSObject {
  external bool get ok;
  external int get status;
  external JSPromise<JSArrayBuffer> arrayBuffer();
}
