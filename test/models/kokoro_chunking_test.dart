import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:fonnx/models/kokoro/kokoro_chunking.dart';
import 'package:fonnx/models/kokoro/kokoro_sentence_splitter.dart';
import 'package:fonnx/models/kokoro/kokoro_normalizer.dart';

void main() {
  test('acoustic policy and crossfade match pinned C++ reference', () {
    final golden =
        jsonDecode(
              File('test/data/goldens/kokoro_chunking.json').readAsStringSync(),
            )
            as Map;
    for (final c in golden['cases'] as List) {
      final frames = c['frames'] as int;
      final policy = KokoroChunkPolicy(
        firstChunkSeconds: (c['first'] as num).toDouble(),
        toleranceSeconds: (c['tolerance'] as num).toDouble(),
      );
      final cost = kokoroBoundaryCost(
        (c['f0'] as List).cast<num>().map((n) => n.toDouble()).toList(),
        (c['energy'] as List).cast<num>().map((n) => n.toDouble()).toList(),
        frames,
      );
      for (var i = 0; i < cost.length; i++) {
        expect(cost[i], closeTo((c['cost'][i] as num).toDouble(), 1e-6));
      }
      final boundaries = kokoroPlanBoundaries(cost, frames, policy: policy);
      expect(boundaries, c['boundaries']);
      final spans = kokoroPlanSpans(boundaries, frames, policy: policy);
      expect([
        for (final s in spans)
          [s.decodeFirst, s.decodeLast, s.keepFirst, s.keepLast],
      ], c['spans']);
      final joiner = KokoroSliceJoiner(policy: policy);
      final joined = <double>[];
      for (var i = 0; i < spans.length; i++) {
        final s = spans[i];
        joined.addAll(
          joiner.add(
            Float32List.fromList([
              for (var j = s.keepFirst; j < s.keepLast; j++) j.toDouble(),
            ]),
            last: i == spans.length - 1,
          ),
        );
      }
      expect(joined.length, c['joined_count']);
      for (var i = 0; i < joined.length; i += 97) {
        expect(
          joined[i],
          closeTo((c['samples'][i ~/ 97] as num).toDouble(), .08),
        );
      }
      expect(
        policy.maxSustainableGrowth(.25),
        closeTo((c['max_growth'] as num).toDouble(), 1e-6),
      );
    }
  });

  test(
    'phoneme splitter preserves code points and bounds every model input',
    () {
      final random = math.Random(7);
      for (var run = 0; run < 100; run++) {
        final words = List.generate(
          1 + random.nextInt(100),
          (_) => 'ɹ' * (1 + random.nextInt(800)),
        );
        final input = words.join(' ');
        final pieces = kokoroSplitPhonemes(input);
        expect(pieces.every((p) => p.runes.length <= 510), isTrue);
        expect(pieces.join().replaceAll(' ', ''), input.replaceAll(' ', ''));
      }
      expect(kokoroSplitPhonemes('😀' * 511).map((s) => s.runes.length), [
        510,
        1,
      ]);
    },
  );

  test('phoneme split includes a space exactly at the token limit', () {
    final text = '${'a' * 499} ${'b' * 10} c';
    expect(kokoroSplitPhonemes(text), ['${'a' * 499} ${'b' * 10}', 'c']);
  });

  test('Moonshine English sentence rules and incremental fragments', () {
    expect(kokoroSplitSentences('Hello ').remainder, 'Hello ');
    expect(kokoroSplitSentences('Hello there. ').units, ['Hello there.']);
    expect(kokoroSplitSentences('3.').units, isEmpty);
    expect(kokoroSplitSentences('3.14 is pi. Next. ', finalInput: true).units, [
      '3.14 is pi.',
      'Next.',
    ]);
    expect(
      kokoroSplitSentences(
        'Dr. Smith met J. R. R. Tolkien. Then left.',
        finalInput: true,
      ).units,
      ['Dr. Smith met J. R. R. Tolkien.', 'Then left.'],
    );
    expect(
      kokoroSplitSentences('“Wait. Stay!” Then go. ', finalInput: true).units,
      ['“Wait. Stay!”', 'Then go.'],
    );
    expect(
      kokoroSplitSentences('Warning: Leave now.', finalInput: true).units,
      ['Warning:', 'Leave now.'],
    );
    expect(kokoroSplitSentences('One. Two. Three.', finalInput: true).units, [
      'One.',
      'Two.',
      'Three.',
    ]);
    expect(
      kokoroSplitSentences(
        'Prof. Smith waited. then left.',
        finalInput: true,
      ).units,
      ['Prof. Smith waited. then left.'],
    );
    expect(
      kokoroSplitSentences('Hi. Longer sentence. ', minCodepoints: 10).units,
      ['Hi. Longer sentence.'],
    );
  });

  test('a spaced ellipsis is one mark', () {
    List<String> split(String s) =>
        kokoroSplitSentences(s, finalInput: true).units;
    expect(split("'. . . were given to understand this. You took him aback."), [
      "'. . . were given to understand this.",
      'You took him aback.',
    ]);
    expect(split('after you . . . did you fool him. Not him.'), [
      'after you . . . did you fool him.',
      'Not him.',
    ]);
    expect(split('And no one . . . . She never understood.'), [
      'And no one . . . .',
      'She never understood.',
    ]);
    expect(split('It ended . . . Then quiet.'), [
      'It ended . . .',
      'Then quiet.',
    ]);
  });

  test('no slice starts in a pause', () {
    // 40 frames per second: speech, a 0.5 s pause, speech, a 0.5 s pause.
    final speech = [
      for (var i = 0; i < 160; i++) (i < 60) || (i >= 80 && i < 140),
    ];
    // Cost is lowest in pauses, as prosody energy makes it at word ends.
    final cost = [for (final s in speech) s ? 1.0 : 0.0];
    final free = kokoroPlanBoundaries(cost, 160);
    expect(free.any((b) => b > 0 && b < 160 && !speech[b]), isTrue);
    final guarded = kokoroPlanBoundaries(cost, 160, speech: speech);
    for (final b in guarded.sublist(1, guarded.length - 1)) {
      final ahead = speech.sublist(b, b + kokoroSpeechWindow);
      final behind = speech.sublist(b - kokoroSpeechWindow, b);
      expect(ahead.where((s) => s).length >= kokoroSpeechMinFrames, isTrue);
      expect(behind.where((s) => s).length >= kokoroSpeechMinFrames, isTrue);
    }
    // The trailing pause joins the last slice.
    expect(
      guarded.sublist(1, guarded.length - 1).every((b) => b < 140),
      isTrue,
    );
    // A leading pause joins the first slice.
    final lead = [for (var i = 0; i < 160; i++) i >= 20];
    final leadCost = [for (final s in lead) s ? 1.0 : 0.0];
    final first = kokoroPlanBoundaries(leadCost, 160, speech: lead)[1];
    expect(first, greaterThanOrEqualTo(20 + kokoroSpeechMinFrames));
    // Energy above 2 is speech.
    expect(kokoroSpeechFrames([6, 6, -9, -9, 3, 2], 3), [true, false, true]);
  });

  test('unmatched quotes and brackets cannot stop later splits', () {
    // Mismatched open and close marks, as in scanned books.
    expect(
      kokoroSplitSentences(
        "'Yes Mario?’ 'Are you asleep?’ 'Yes. I can't be.’ Then quiet.",
        finalInput: true,
      ).units,
      [
        "'Yes Mario?’",
        "'Are you asleep?’",
        "'Yes.",
        "I can't be.’",
        'Then quiet.',
      ],
    );
    // One closer clears a nested open quote.
    expect(
      kokoroSplitSentences('«A «b» done. Next one.', finalInput: true).units,
      ['«A «b» done.', 'Next one.'],
    );
    // An unclosed quote or bracket stops holding sentence ends after openLimit.
    final long = List.filled(10, 'Word word word.').join(' ');
    for (final open in ['«', '(']) {
      final units = kokoroSplitSentences(
        '$open$long',
        finalInput: true,
        openLimit: 40,
      ).units;
      expect(
        units.first,
        '$open${List.filled(3, 'Word word word.').join(' ')}',
      );
      expect(units.length, 8);
    }
    // Within the limit, an open quote still keeps its sentences together.
    expect(
      kokoroSplitSentences('“Wait. Stay! Go. Now.', finalInput: true).units,
      ['“Wait. Stay! Go. Now.'],
    );
  });

  test(
    'normalizer handles times, units, addresses and preserves overrides',
    () {
      expect(
        normalizeKokoroEnglish('At 3:30, bring 5kg and 16GB.'),
        'At 3 30, bring 5 kilograms and 16 gigabytes.',
      );
      expect(
        normalizeKokoroEnglish('At 09:05 & 12:00.'),
        "At 9 oh 5  and  12 o'clock.",
      );
      expect(
        normalizeKokoroEnglish('Visit https://example.com/a.'),
        'Visit example dot com slash a.',
      );
      expect(
        normalizeKokoroEnglish('a_b@example.com'),
        'a underscore b at example dot com',
      );
      expect(normalizeKokoroEnglish('[name](/kˈOkəɹO/)'), '[name](/kˈOkəɹO/)');
    },
  );
}
