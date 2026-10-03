import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fonnx/fonnx.dart';

const _bundle = 'example/assets/models/futoSwipe';

/// Public-API tests against the converted bundle and native ONNX Runtime.
void main() {
  final fixture =
      jsonDecode(
            utf8.decode(
              gzip.decode(
                File('test/data/futo_swipe/replay.json.gz').readAsBytesSync(),
              ),
            ),
          )
          as Map;
  final cases = (fixture['cases'] as List).cast<Map>();
  final goldens =
      (jsonDecode(
                utf8.decode(
                  gzip.decode(
                    File(
                      'test/data/futo_swipe/goldens.json.gz',
                    ).readAsBytesSync(),
                  ),
                ),
              )
              as List)
          .cast<Map>();

  List<FutoSwipePoint> trace(Map c) => [
    for (final p in (c['points'] as List).cast<List>())
      FutoSwipePoint(
        (p[1] as num).toDouble(),
        (p[2] as num).toDouble(),
        Duration(milliseconds: p[0] as int),
      ),
  ];

  late FutoSwipe swipe;
  setUpAll(() async {
    swipe = await FutoSwipe.load(
      bundle: FutoSwipeBundle.fromDirectory(_bundle),
    );
  });
  tearDownAll(() => swipe.close());

  test('loads every swipeable model vocabulary word', () {
    final vocabulary = File(
      '$_bundle/hungry_jellyfish/vocab.txt',
    ).readAsLinesSync();
    final swipeable = vocabulary.where(
      (w) => RegExp(
        r'^[a-z]+$',
      ).hasMatch(w.toLowerCase().replaceAll(RegExp("['\u2019]"), '')),
    );
    expect(swipe.lexiconSize, swipeable.length);
  });

  for (var i = 0; i < 3; i++) {
    test('raw trace $i reaches the ExecuTorch greedy path', () async {
      final emissions = await swipe.emissions(trace(cases[i]));
      final decoder = goldens.singleWhere(
        (g) => g['model'] == 'decoder' && g['label'] == 'public swipe $i',
      );
      final expected = (decoder['outputs'][0]['data'] as List).cast<num>();
      int best(double Function(int) score, int t) {
        var winner = 0;
        for (var c = 1; c < 27; c++) {
          if (score(t * 27 + c) > score(t * 27 + winner)) winner = c;
        }
        return winner;
      }

      expect(
        [for (var t = 0; t < 32; t++) best((j) => emissions.logScores[j], t)],
        [for (var t = 0; t < 32; t++) best((j) => expected[j].toDouble(), t)],
      );
    });
  }

  test('decodes public swipes to their targets', () async {
    // Model vocabulary only: check targets this lexicon contains and that the
    // frozen ExecuTorch replay ranked first with its larger lexicon.
    final keys = File(
      '$_bundle/hungry_jellyfish/vocab.txt',
    ).readAsLinesSync().map((w) => w.toLowerCase()).toSet();
    var checked = 0;
    for (final c in cases.take(40)) {
      final target = c['target'] as String;
      final frozenTop = (c['top3'] as List).first;
      if (frozenTop != target || !keys.contains(target)) continue;
      final results = await swipe.decode(trace(c));
      expect(results, hasLength(3));
      expect(
        results.map((r) => r.searchKey),
        contains(target),
        reason: 'row ${c['row']}',
      );
      checked++;
    }
    expect(checked, greaterThan(10));
  });

  test('context ranking uses the contextual configuration', () async {
    final points = trace(cases[0]);
    final plain = await swipe.decode(points, maxCandidates: 10);
    final contextual = await swipe.decode(
      points,
      previousWords: const ['I', 'would', 'like', 'to', 'read', 'the'],
      maxCandidates: 10,
    );
    expect(plain, isNotEmpty);
    expect(contextual, isNotEmpty);
    // Different weight sets produce different absolute scores.
    expect(contextual.first.score, isNot(plain.first.score));
    for (final r in [...plain, ...contextual]) {
      expect(r.score.isFinite, isTrue);
    }
  });

  test('next-word scores agree with direct word scores', () async {
    const context = ['I', 'went', 'to', 'the'];
    final predicted = await swipe.predictNextWords(context, count: 5);
    expect(predicted, hasLength(5));
    for (var i = 1; i < predicted.length; i++) {
      expect(predicted[i - 1].score, greaterThanOrEqualTo(predicted[i].score));
    }
    final direct = await swipe.scoreWords(context, [
      for (final p in predicted) p.word,
    ]);
    for (var i = 0; i < predicted.length; i++) {
      expect(direct[i], closeTo(predicted[i].score, 1e-4));
    }
    // Out-of-vocabulary words use hashed rows and still score.
    final oov = await swipe.scoreWords(context, ['telosnexian']);
    expect(oov.single.isFinite, isTrue);
  });

  test('personal words become swipeable without retraining', () async {
    final layout = FutoSwipeLayout.englishQwerty();
    final path = <FutoSwipePoint>[];
    // A synthetic swipe through the key centers of "telosnex".
    const word = 'telosnex';
    for (var i = 0; i < word.length - 1; i++) {
      final (x0, y0) = layout.keyCenters[word[i]]!;
      final (x1, y1) = layout.keyCenters[word[i + 1]]!;
      for (var s = 0; s < 8; s++) {
        final f = s / 8;
        path.add(
          FutoSwipePoint(
            x0 + (x1 - x0) * f,
            y0 + (y1 - y0) * f,
            Duration(milliseconds: (i * 8 + s) * 12),
          ),
        );
      }
    }
    final (xe, ye) = layout.keyCenters['x']!;
    path.add(FutoSwipePoint(xe, ye, Duration(milliseconds: 7 * 8 * 12)));

    final before = await swipe.decode(path, maxCandidates: 5);
    expect(before.map((r) => r.searchKey), isNot(contains('telosnex')));
    final size = await swipe.setLexicon(const [
      FutoSwipeWord('Telosnex', frequency: 200),
    ]);
    expect(size, swipe.lexiconSize);
    try {
      final after = await swipe.decode(path, maxCandidates: 5);
      expect(after.first.word, 'Telosnex');
      expect(after.first.searchKey, 'telosnex');
    } finally {
      await swipe.setLexicon(const []);
    }
  });

  test('validates arguments before queueing work', () {
    expect(() => swipe.decode(const []), throwsArgumentError);
    expect(
      () => swipe.decode(trace(cases[0]), maxCandidates: 0),
      throwsArgumentError,
    );
    expect(
      () => swipe.predictNextWords(const ['a'], count: 0),
      throwsArgumentError,
    );
    expect(
      () => swipe.scoreWords(const [''], const ['a']),
      throwsArgumentError,
    );
    expect(
      () => FutoSwipe.load(
        bundle: FutoSwipeBundle.fromDirectory(_bundle),
        beamWidth: 0,
      ),
      throwsArgumentError,
    );
  });

  test('missing models fail load and closed instances reject work', () async {
    await expectLater(
      FutoSwipe.load(bundle: FutoSwipeBundle.fromDirectory('/nonexistent')),
      throwsA(anything),
    );
    final second = await FutoSwipe.load(
      bundle: FutoSwipeBundle.fromDirectory(_bundle),
      includeModelVocabulary: false,
      lexicon: const [FutoSwipeWord('hello')],
    );
    expect(second.lexiconSize, 1);
    await second.close();
    await second.close();
    expect(() => second.decode(trace(cases[0])), throwsStateError);
  });
}
