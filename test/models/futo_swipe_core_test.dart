import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fonnx/models/futo_swipe/futo_swipe.dart';
import 'package:fonnx/models/futo_swipe/src/context_hash.dart';
import 'package:fonnx/models/futo_swipe/src/ctc_prefix_search.dart';
import 'package:fonnx/models/futo_swipe/src/futo_swipe_engine.dart';
import 'package:fonnx/models/futo_swipe/src/trace_resampler.dart';

const _bundle = 'example/assets/models/futoSwipe';

void main() {
  group('ContextLM hash', () {
    test('matches reference output at block boundaries and for UTF-8', () {
      // Black-box vectors from the pinned reference tool.
      const repeated = {
        0: '146a6b2ea9984c76',
        1: 'fb7f75daf715267',
        3: 'fc52bcfc13b9e36c',
        4: '861f258f0cd53185',
        16: '576433cd745f55f5',
        17: '8729ce1894c1b59e',
        32: 'd89066cdb17c1025',
        48: '4c17422a31f57bd7',
        49: '14ecc0fe1d3d1057',
        64: '7eeaf0a2653eaf15',
        96: '28323fd57d971a11',
        127: '76c36a3e9d7d736a',
      };
      for (final entry in repeated.entries) {
        expect(futoContextHash('x' * entry.key).toRadixString(16), entry.value);
      }
      const unicode = {
        'Telosnex': '57742fef5dc6242',
        'café': 'c88c105f5e352f4f',
        '👩🏽‍💻': 'f7623ebcc0f9a864',
        'microfinance': '5394b758773b8519',
      };
      for (final entry in unicode.entries) {
        expect(futoContextHash(entry.key).toRadixString(16), entry.value);
        expect(
          futoContextBuckets(entry.key),
          everyElement(inInclusiveRange(0, 32767)),
        );
      }
    });
  });

  group('CTC prefix search', () {
    test('unpruned recurrence agrees with every three-frame alignment', () {
      final root = LexiconNode('', -1);
      for (final word in ['a', 'b', 'aa', 'ab', 'ba', 'bb', 'aba', 'bab']) {
        addLexiconWord(root, word, 0);
      }
      final probabilities = [0.6, 0.3, 0.1, 0.2, 0.3, 0.5, 0.5, 0.4, 0.1];
      final logs = Float32List.fromList(probabilities.map(math.log).toList());
      final brute = <String, double>{};
      for (var encoded = 0; encoded < 27; encoded++) {
        var x = encoded, previous = -1, word = '', probability = 1.0;
        for (var t = 0; t < 3; t++) {
          final c = x % 3;
          x ~/= 3;
          probability *= probabilities[t * 3 + c];
          if (c != previous && c != 2) word += String.fromCharCode(97 + c);
          previous = c;
        }
        brute.update(word, (p) => p + probability, ifAbsent: () => probability);
      }
      final actual = ctcPrefixSearch(logs, 3, 3, root, beam: 1000);
      for (final entry in actual.entries) {
        expect(
          math.exp(entry.value.total),
          closeTo(brute[entry.key.text] ?? 0, 1e-6),
        );
      }
      // This trie contains every possible collapsed three-frame path.
      expect(
        actual.values.fold(0.0, (sum, m) => sum + math.exp(m.total)),
        closeTo(1, 1e-6),
      );
    });

    test('search keys keep display spellings and skip unswipeable words', () {
      expect(lexiconSearchKey("Don't"), 'dont');
      expect(lexiconSearchKey('don\u2019t'), 'dont');
      expect(lexiconSearchKey('e-mail'), isNull);
      expect(lexiconSearchKey('café'), isNull);
      expect(lexiconSearchKey("'"), isNull);
      final root = LexiconNode('', -1);
      expect(addLexiconWord(root, "don't", 200), isTrue);
      expect(addLexiconWord(root, 'dont', 10), isTrue);
      expect(addLexiconWord(root, "don't", 50), isTrue);
      expect(addLexiconWord(root, '42', 0), isFalse);
      var node = root;
      for (final c in 'dont'.codeUnits) {
        node = node.children[c - 97]!;
      }
      expect(node.surfaces.map((s) => (s.text, s.frequency)), [
        ("don't", 200),
        ('dont', 10),
      ]);
      expect(node.frequency, 200);
    });
  });

  group('trace resampling', () {
    test('reproduces the published NumPy features bit for bit', () {
      final fixture =
          jsonDecode(
                utf8.decode(
                  gzip.decode(
                    File(
                      'test/data/futo_swipe/replay.json.gz',
                    ).readAsBytesSync(),
                  ),
                ),
              )
              as Map;
      final cases = fixture['cases'] as List;
      expect(cases, hasLength(1000));
      var zeroDuration = 0, duplicateTimes = 0;
      for (final c in cases) {
        final points = (c['points'] as List).cast<List>();
        final trace = [
          for (final p in points)
            FutoSwipePoint(
              (p[1] as num).toDouble(),
              (p[2] as num).toDouble(),
              Duration(milliseconds: p[0] as int),
            ),
        ];
        if (points.last[0] == points.first[0]) zeroDuration++;
        for (var i = 1; i < points.length; i++) {
          if (points[i][0] == points[i - 1][0]) {
            duplicateTimes++;
            break;
          }
        }
        final expected = Float32List.fromList(
          (c['features'] as List).map((v) => (v as num).toDouble()).toList(),
        );
        final actual = resampleFutoTrace(validatedFutoTrace(trace));
        expect(actual, orderedEquals(expected), reason: 'row ${c['row']}');
      }
      // The fixture exercises both NumPy edge paths.
      expect(zeroDuration, greaterThan(0));
      expect(duplicateTimes, greaterThan(0));
    });

    test('rejects empty, non-finite, and time-reversed traces', () {
      expect(() => validatedFutoTrace(const []), throwsArgumentError);
      expect(
        () => validatedFutoTrace([
          const FutoSwipePoint(double.nan, 0, Duration.zero),
        ]),
        throwsArgumentError,
      );
      expect(
        () => validatedFutoTrace([
          const FutoSwipePoint(0, 0, Duration(milliseconds: 5)),
          const FutoSwipePoint(0, 0, Duration(milliseconds: 4)),
        ]),
        throwsArgumentError,
      );
    });
  });

  group('layout', () {
    test('standard QWERTY matches the validation geometry', () {
      final keys = FutoSwipeLayout.englishQwerty().toKeyTensor();
      expect(keys[(ord('q')) * 2], closeTo(0.05, 1e-7));
      expect(keys[(ord('a')) * 2], closeTo(0.10, 1e-7));
      expect(keys[(ord('z')) * 2 + 1], closeTo(5 / 6, 1e-7));
      expect(keys.sublist(52), everyElement(0));
      final mask = FutoSwipeLayout.englishQwerty().toMaskTensor();
      expect(mask.sublist(0, 26), everyElement(1));
      expect(mask.sublist(26), everyElement(0));
    });

    test('requires exactly a-z with finite centers', () {
      final valid = FutoSwipeLayout.englishQwerty().keyCenters;
      expect(
        () => FutoSwipeLayout({...valid}..remove('q')),
        throwsArgumentError,
      );
      expect(
        () => FutoSwipeLayout({...valid, 'q': (double.infinity, 0)}),
        throwsArgumentError,
      );
      expect(
        () => FutoSwipeLayout(
          {...valid}
            ..remove('q')
            ..['!'] = (0, 0),
        ),
        throwsArgumentError,
      );
    });
  });

  group('engine', () {
    late Map<String, dynamic> scoring;
    setUpAll(() {
      scoring =
          jsonDecode(File('$_bundle/scoring.json').readAsStringSync())
              as Map<String, dynamic>;
    });

    test('ranks lexicon words from decoder emissions', () async {
      final backend = _FakeBackend(emissions: _spell('cat'));
      final engine = await _engine(
        backend,
        scoring,
        lexicon: const [
          FutoSwipeWord('car', frequency: 255),
          FutoSwipeWord('cat'),
          FutoSwipeWord('Cat', frequency: 100),
          FutoSwipeWord('dog', frequency: 255),
        ],
      );
      final results = await engine.decode(
        _trace,
        FutoSwipeLayout.englishQwerty(),
        maxCandidates: 3,
      );
      expect(results.first.searchKey, 'cat');
      // Same key: the higher-frequency spelling wins; the other is kept.
      expect(results.first.word, 'Cat');
      expect(results.first.alternatives, ['cat']);
      // Every reachable word is a candidate; an unrelated one ranks last.
      expect(results.last.searchKey, 'dog');
      expect(results.last.score, lessThan(results.first.score - 10));
      expect(results.length, lessThanOrEqualTo(3));
      for (var i = 1; i < results.length; i++) {
        expect(results[i - 1].score, greaterThanOrEqualTo(results[i].score));
      }
      expect(backend.decoderInputs.single, hasLength(32 * 92));
      expect(backend.contextCalls, 0);
    });

    test(
      'builds decoder input from letters, blank, coefficients, intention',
      () async {
        final backend = _FakeBackend(emissions: _spell('a'));
        final engine = await _engine(backend, scoring);
        await engine.emissions(_trace, FutoSwipeLayout.englishQwerty());
        final input = backend.decoderInputs.single;
        for (var t = 0; t < 32; t++) {
          for (var c = 0; c < 26; c++) {
            expect(input[t * 92 + c], _encoderValue(0, t, c));
          }
          expect(input[t * 92 + 26], _encoderValue(0, t, 64));
          for (var c = 0; c < 64; c++) {
            expect(input[t * 92 + 27 + c], _encoderValue(1, t, c));
          }
          expect(input[t * 92 + 91], _encoderValue(2, t, 0));
        }
        final keys = backend.layoutKeys.single;
        expect(keys, FutoSwipeLayout.englishQwerty().toKeyTensor());
      },
    );

    test('rejects non-finite decoder output', () async {
      final emissions = _spell('a')..[5] = double.nan;
      final engine = await _engine(_FakeBackend(emissions: emissions), scoring);
      await expectLater(
        engine.emissions(_trace, FutoSwipeLayout.englishQwerty()),
        throwsStateError,
      );
    });

    test('context scores use exact, lowercase, and hashed rows', () async {
      final backend = _FakeBackend(emissions: _spell('a'));
      final engine = await _engine(backend, scoring);
      final scores = await engine.scoreWords(
        ['alpha', 'Unknown'],
        ['alpha', 'ALPHA', 'zzz-not-in-vocab', _vocabulary.last],
      );
      // Position 1 is the final real context word.
      final state = backend.contextState(1);
      final alpha = _vocabulary.indexOf('alpha') + 1;
      expect(scores[0], closeTo(_exactScore(state, alpha), 1e-4));
      expect(scores[1], closeTo(_exactScore(state, alpha), 1e-4));
      expect(scores[2], closeTo(_hashedScore(state, 'zzz-not-in-vocab'), 1e-4));
      // The final vocabulary word has no exact row and must be hashed.
      expect(scores[3], closeTo(_hashedScore(state, _vocabulary.last), 1e-4));

      final (ids, buckets) = backend.contextInputs.single;
      expect(ids.sublist(0, 2), [alpha, futoContextHashedTokenId]);
      expect(ids.sublist(2), everyElement(0));
      expect(buckets.sublist(0, 2), [0, 0]);
      expect(buckets.sublist(2, 4), futoContextBuckets('Unknown'));
    });

    test('context state is cached and truncated to 16 words', () async {
      final backend = _FakeBackend(emissions: _spell('a'));
      final engine = await _engine(backend, scoring);
      final long = [for (var i = 0; i < 20; i++) 'w$i'];
      await engine.scoreWords(long, ['alpha']);
      await engine.scoreWords(long, ['beta']);
      await engine.predictNextWords(long, 3);
      expect(backend.contextCalls, 1);
      final (ids, buckets) = backend.contextInputs.single;
      expect(ids, everyElement(futoContextHashedTokenId));
      expect(buckets.sublist(0, 2), futoContextBuckets('w4'));
      await engine.scoreWords(['alpha'], ['beta']);
      expect(backend.contextCalls, 2);
      // An empty context reads the first (padded) position.
      await engine.scoreWords(const [], ['beta']);
      expect(backend.contextCalls, 3);
      expect(backend.contextInputs.last.$1, everyElement(0));
    });

    test(
      'predictNextWords returns the exact top-k vocabulary scores',
      () async {
        final backend = _FakeBackend(emissions: _spell('a'));
        final engine = await _engine(backend, scoring);
        final results = await engine.predictNextWords(['alpha'], 7);
        final state = backend.contextState(0);
        final expected = [
          for (var id = 1; id < futoContextVocabularySize; id++)
            FutoWordScore(_vocabulary[id - 1], _exactScore(state, id)),
        ]..sort((a, b) => b.score.compareTo(a.score));
        expect(results.map((r) => r.word), expected.take(7).map((r) => r.word));
        for (var i = 0; i < 7; i++) {
          expect(results[i].score, closeTo(expected[i].score, 1e-4));
        }
      },
    );

    test('context changes swipe ranking only through alpha', () async {
      final backend = _FakeBackend(emissions: _spell('cat'));
      final engine = await _engine(
        backend,
        scoring,
        lexicon: const [FutoSwipeWord('cat'), FutoSwipeWord('cast')],
      );
      final layout = FutoSwipeLayout.englishQwerty();
      final withContext = await engine.decode(
        _trace,
        layout,
        previousWords: const ['alpha'],
        maxCandidates: 5,
      );
      final weights = engine.contextWeights;
      final state = backend.contextState(0);
      final noContextEngine = await _engine(
        _FakeBackend(emissions: _spell('cat')),
        scoring,
        lexicon: const [FutoSwipeWord('cat'), FutoSwipeWord('cast')],
      );
      final plain = await noContextEngine.decode(
        _trace,
        layout,
        maxCandidates: 5,
      );
      expect(plain.first.searchKey, 'cat');
      final cat = withContext.singleWhere((c) => c.searchKey == 'cat');
      expect(
        cat.score,
        closeTo(
          _ctcBase(engine.contextWeights, 'cat', _spell('cat')) +
              weights.alpha *
                  _exactScore(state, _vocabulary.indexOf('cat') + 1),
          1e-3,
        ),
      );
    });

    test('setLexicon replaces words atomically and counts them', () async {
      final engine = await _engine(
        _FakeBackend(emissions: _spell('cat')),
        scoring,
        lexicon: const [FutoSwipeWord('cat'), FutoSwipeWord('e-mail')],
      );
      expect(engine.lexiconSize, 1);
      engine.setLexicon(const [
        FutoSwipeWord('dog'),
      ], includeModelVocabulary: false);
      expect(engine.lexiconSize, 1);
      final results = await engine.decode(
        _trace,
        FutoSwipeLayout.englishQwerty(),
        maxCandidates: 3,
      );
      expect(results.map((r) => r.searchKey), isNot(contains('cat')));
      engine.setLexicon(const [], includeModelVocabulary: true);
      // Only purely alphabetic fake vocabulary words are swipeable.
      expect(engine.lexiconSize, _vocabulary.where(_swipeable).length);
    });

    test('rejects a mismatched vocabulary and closes the backend', () async {
      final backend = _FakeBackend(emissions: _spell('a'));
      await expectLater(
        FutoSwipeEngine.create(
          backend: backend,
          vocabulary: const ['only'],
          scoring: scoring,
          lexicon: const [],
          includeModelVocabulary: false,
          beamWidth: 300,
        ),
        throwsFormatException,
      );
      final engine = await _engine(backend, scoring);
      await engine.close();
      expect(backend.closed, isTrue);
      await expectLater(
        engine.scoreWords(const [], const ['a']),
        throwsStateError,
      );
    });
  });

  test('lexicon validation snapshots words and rejects bad frequency', () {
    expect(
      () => validatedFutoLexicon(const [FutoSwipeWord('x', frequency: 256)]),
      throwsArgumentError,
    );
    expect(
      () => validatedFutoLexicon(const [FutoSwipeWord(' ')]),
      throwsArgumentError,
    );
    final source = [const FutoSwipeWord('a')];
    final snapshot = validatedFutoLexicon(source);
    source.add(const FutoSwipeWord('b'));
    expect(snapshot, hasLength(1));
    expect(() => validatedFutoWords(const [''], 'words'), throwsArgumentError);
  });
}

int ord(String letter) => letter.codeUnitAt(0) - 97;

bool _swipeable(String word) => lexiconSearchKey(word) != null;

final _trace = [
  const FutoSwipePoint(0.1, 0.5, Duration.zero),
  const FutoSwipePoint(0.5, 0.5, Duration(milliseconds: 200)),
];

/// 32,768 words: a few real words, then non-alphabetic filler.
final _vocabulary = [
  'alpha',
  'beta',
  'Gamma',
  'cat',
  for (var i = 4; i < futoContextVocabularySize - 1; i++) 'v$i',
  'finalword',
];

Future<FutoSwipeEngine> _engine(
  _FakeBackend backend,
  Map<String, dynamic> scoring, {
  List<FutoSwipeWord> lexicon = const [],
}) => FutoSwipeEngine.create(
  backend: backend,
  vocabulary: _vocabulary,
  scoring: scoring,
  lexicon: lexicon,
  includeModelVocabulary: false,
  beamWidth: 300,
);

/// Decoder log scores that spell [word] with one letter per step.
Float32List _spell(String word) {
  final logits = Float32List(32 * 27)..fillRange(0, 32 * 27, math.log(1e-4));
  for (var t = 0; t < 32; t++) {
    final letter = t < word.length ? word.codeUnitAt(t) - 97 : 26;
    logits[t * 27 + letter] = math.log(0.9);
  }
  return logits;
}

double _encoderValue(int output, int step, int index) =>
    output * 1000 + step * 100 + index * 0.5;

double _embedding(int table, int row, int d) =>
    math.sin(row * 0.37 + d * 1.3 + table);

double _bias(int table, int row) => math.cos(row * 0.11 + table) * 0.5;

double _exactScore(Float32List state, int id) {
  var score = Float32List.fromList([_bias(0, id)])[0].toDouble();
  for (var d = 0; d < 16; d++) {
    score += state[d] * Float32List.fromList([_embedding(0, id, d)])[0];
  }
  return score;
}

double _hashedScore(Float32List state, String word) {
  var score = 0.0;
  for (final row in futoContextBuckets(word)) {
    score += Float32List.fromList([_bias(1, row)])[0];
    for (var d = 0; d < 16; d++) {
      score += state[d] * Float32List.fromList([_embedding(1, row, d)])[0];
    }
  }
  return score;
}

double _ctcBase(FutoScoringWeights weights, String word, Float32List logits) {
  final root = LexiconNode('', -1);
  addLexiconWord(root, word, 0);
  final states = ctcPrefixSearch(
    logits,
    32,
    27,
    root,
    beam: 300,
    gamma: weights.gammaPrune,
    beta: weights.betaPrune,
  );
  final mass = states.entries.singleWhere((e) => e.key.text == word).value;
  return mass.total / math.pow(word.length, weights.gamma) +
      weights.beta * word.length;
}

final class _FakeBackend implements FutoSwipeOnnxBackend {
  _FakeBackend({required this.emissions});

  final Float32List emissions;
  final decoderInputs = <Float32List>[];
  final layoutKeys = <Float32List>[];
  final contextInputs = <(Int32List, Int32List)>[];
  var contextCalls = 0;
  var closed = false;

  /// Deterministic state for context position [position].
  Float32List contextState(int position) => Float32List.fromList([
    for (var d = 0; d < 16; d++) math.sin(position + d * 0.7),
  ]);

  @override
  Future<FutoEncoderOutput> runEncoder(
    Float32List features,
    Float32List layoutKeys,
    Uint8List layoutMask,
  ) async {
    expect(features, hasLength(128));
    this.layoutKeys.add(Float32List.fromList(layoutKeys));
    Float32List table(int output, int width) => Float32List.fromList([
      for (var t = 0; t < 32; t++)
        for (var c = 0; c < width; c++) _encoderValue(output, t, c),
    ]);
    return FutoEncoderOutput(
      logEmissions: table(0, 65),
      coefficients: table(1, 64),
      intention: table(2, 1),
    );
  }

  @override
  Future<Float32List> runDecoder(Float32List features) async {
    decoderInputs.add(Float32List.fromList(features));
    return Float32List.fromList(emissions);
  }

  @override
  Future<Float32List> runContext(
    Int32List tokenIds,
    Int32List hashBuckets,
  ) async {
    contextCalls++;
    contextInputs.add((
      Int32List.fromList(tokenIds),
      Int32List.fromList(hashBuckets),
    ));
    return Float32List.fromList([
      for (var p = 0; p < 16; p++) ...contextState(p),
    ]);
  }

  @override
  Future<FutoContextEmbeddings> loadEmbeddings() async {
    Float32List table(int index) => Float32List.fromList([
      for (var row = 0; row < futoContextVocabularySize; row++)
        for (var d = 0; d < 16; d++) _embedding(index, row, d),
    ]);
    Float32List biases(int index) => Float32List.fromList([
      for (var row = 0; row < futoContextVocabularySize; row++)
        _bias(index, row),
    ]);
    return FutoContextEmbeddings(
      exactEmbeddings: table(0),
      exactBiases: biases(0),
      hashedEmbeddings: table(1),
      hashedBiases: biases(1),
    );
  }

  @override
  Future<void> close() async => closed = true;
}
