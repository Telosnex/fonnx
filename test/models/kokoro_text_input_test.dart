import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:test/test.dart';
// Only kokoro.dart: the splitter must be exported from it.
import 'package:fonnx/models/kokoro/kokoro.dart';

/// Renders each unit as one chunk whose text is the unit. When [gate] is set,
/// rendering waits for it, like a slow model.
class _FakeKokoro extends Kokoro {
  final rendered = <String>[];
  Completer<void>? gate;

  @override
  Map<String, KokoroVoice> get voices => const {
    'v': KokoroVoice(path: '', language: KokoroLanguage.americanEnglish),
  };

  @override
  Stream<KokoroChunk> renderUtterance(
    String text, {
    required String voice,
    required double speed,
    required bool normalize,
  }) async* {
    rendered.add(text);
    await gate?.future;
    yield KokoroChunk(
      samples: Float32List(1),
      utteranceId: rendered.length,
      isFinal: true,
      text: text,
    );
  }

  @override
  Future<void> dispose() async {}
}

Future<List<String>> _texts(KokoroTextInput input) =>
    input.audio.map((c) => c.text!).toList();

final _goOn = List.filled(4000, 'Go on.').join(' ');

const _corpus = [
  'It costs 3.5 dollars. Dr. Smith said so. Then he left!',
  'He said "Stop. Now." Then left... Wait . . . why? '
      'Because: reasons. e.g. this, U.S. policy; approx. five.',
  '“Wait. Stay!” Then go. (See fig. 2.) Done? Yes. 你好。再见！',
  'Warning: Leave now. One. Two. Three. vol. 2 is here. OK.',
  'Prof. Smith waited. then left. Is it? Yes!! Really?! "Fine." (Okay.) '
      'The end.',
  'Results:\n\n- Item one. - Item two.\n## Heading\nThe test passed.  '
      'It took 12.5 s. Mr. and Mrs. Lee came at 3 p.m. today. Bye.',
  'Hi. Longer sentence here. A. B. C. Short. Another long sentence ends here.',
  '«A «b» done. Next one. \'Yes Mario?’ \'Are you asleep?’ \'Yes. I can\'t.’ '
      'Then quiet... Wait… What?',
];

/// Random fragments of [text]: mostly 1 to 6 UTF-16 units, sometimes empty,
/// sometimes long. Cuts never split a surrogate pair.
List<String> _fragments(String text, Random random) {
  final fragments = <String>[];
  var i = 0;
  while (i < text.length) {
    final roll = random.nextInt(10);
    var size = roll == 0
        ? 0
        : roll == 1
        ? 10 + random.nextInt(30)
        : 1 + random.nextInt(6);
    var end = min(text.length, i + size);
    if (end < text.length &&
        end > 0 &&
        text.codeUnitAt(end - 1) >= 0xD800 &&
        text.codeUnitAt(end - 1) <= 0xDBFF) {
      end++;
    }
    fragments.add(text.substring(i, end));
    i = end;
  }
  return fragments;
}

void main() {
  test('many one-character adds before listening do not throw', () async {
    final engine = _FakeKokoro();
    final input = engine.input(voice: 'v');
    for (var i = 0; i < 20000; i++) {
      input.add(_goOn[i]);
    }
    await input.close();
    expect(
      await _texts(input),
      kokoroSplitSentences(_goOn.substring(0, 20000), finalInput: true).units,
    );
  });

  test('many one-character adds while a unit renders do not throw', () async {
    final engine = _FakeKokoro()..gate = Completer<void>();
    final input = engine.input(voice: 'v')..add('First! ');
    final texts = _texts(input);
    await pumpEventQueue();
    expect(engine.rendered, ['First!']);
    for (var i = 0; i < 5000; i++) {
      input.add(_goOn[i]);
    }
    engine.gate!.complete();
    await input.close();
    expect(await texts, [
      'First!',
      ...kokoroSplitSentences(_goOn.substring(0, 5000), finalInput: true).units,
    ]);
  });

  test('flushes read together keep their order', () async {
    final engine = _FakeKokoro();
    final input = engine.input(voice: 'v')
      ..add('A')
      ..flush()
      ..add('b c')
      ..flush()
      ..flush()
      ..add('Done. And')
      ..add(' more');
    await input.close();
    expect(await _texts(input), ['A', 'b c', 'Done.', 'And more']);
  });

  test('flush with no new text speaks the carried text', () async {
    final engine = _FakeKokoro();
    final input = engine.input(voice: 'v')..add('No end');
    final texts = _texts(input);
    await pumpEventQueue();
    expect(engine.rendered, isEmpty);
    input.flush();
    await pumpEventQueue();
    expect(engine.rendered, ['No end']);
    input.add('Next.');
    await input.close();
    expect(await texts, ['No end', 'Next.']);
  });

  test('I3: flush speaks held text before the next add is read', () async {
    final engine = _FakeKokoro();
    // D3 holds "Let me check.": a closer or a next word can still follow.
    final input = engine.input(voice: 'v')..add('Let me check.');
    final texts = _texts(input);
    await pumpEventQueue();
    expect(engine.rendered, isEmpty);
    input
      ..flush()
      ..add(' found it.');
    await pumpEventQueue();
    expect(engine.rendered, ['Let me check.']);
    await input.close();
    expect(await texts, ['Let me check.', 'found it.']);
  });

  test('I4: source ranges match the added text', () async {
    final random = Random(4);
    for (final text in _corpus) {
      for (var n = 0; n < 40; n++) {
        final engine = _FakeKokoro();
        final input = engine.input(voice: 'v');
        final chunks = input.audio.toList();
        final added = StringBuffer();
        for (final fragment in _fragments(text, random)) {
          input.add(fragment);
          added.write(fragment);
          if (random.nextInt(8) == 0) input.flush();
          if (random.nextInt(3) == 0) await pumpEventQueue(times: 2);
        }
        await input.close();
        final source = added.toString();
        var end = 0;
        for (final chunk in await chunks) {
          final start = chunk.sourceStart!;
          expect(start, greaterThanOrEqualTo(end), reason: text);
          end = chunk.sourceEnd!;
          expect(end, lessThanOrEqualTo(source.length));
          expect(source.substring(start, end), chunk.text, reason: text);
        }
      }
    }
  });

  test('source ranges are null for speak', () async {
    final chunks = await _FakeKokoro().speak('One. Two.', voice: 'v').toList();
    expect(chunks.map((c) => c.sourceStart), [null, null]);
  });

  test('prepare renders once and checks the voice', () async {
    final engine = _FakeKokoro();
    await engine.prepare('v');
    expect(engine.rendered, ['Hi.']);
    expect(() => engine.prepare('nope'), throwsArgumentError);
  });

  test('the pending limit is 64K characters', () {
    final input = _FakeKokoro().input(voice: 'v')..add('a' * 65536);
    expect(() => input.add('b'), throwsStateError);
  });

  test('unterminated text over 64K is an error on audio', () async {
    final input = _FakeKokoro().input(voice: 'v');
    final errors = <Object>[];
    final done = Completer<void>();
    input.audio.listen(null, onError: errors.add, onDone: done.complete);
    input.add('a' * 40000);
    await pumpEventQueue();
    input.add('a' * 30000);
    await done.future;
    expect(errors.single, isStateError);
  });

  test('cancel while waiting for text ends at once', () async {
    final input = _FakeKokoro().input(voice: 'v');
    final subscription = input.audio.listen(null);
    await pumpEventQueue();
    await subscription.cancel().timeout(const Duration(seconds: 1));
    expect(() => input.add('x'), throwsStateError);
  });

  test('kokoroSplitMayChange examples', () {
    expect(kokoroSplitMayChange('Hello', ' world'), isFalse);
    expect(kokoroSplitMayChange('Hello', ' world.'), isTrue);
    expect(kokoroSplitMayChange('Hello.', ' w'), isTrue);
    expect(kokoroSplitMayChange('Hello. ', 'w'), isTrue);
    expect(kokoroSplitMayChange('He said "Stop.', '" Then'), isTrue);
    expect(kokoroSplitMayChange('It is 3.5', ' units'), isFalse);
    expect(kokoroSplitMayChange('', 'plain'), isFalse);
  });

  test('I1: the splitter gives the same units for any fragments', () {
    final random = Random(1);
    var runs = 0;
    for (final text in _corpus) {
      for (final minCodepoints in [0, 12]) {
        final whole = kokoroSplitSentences(
          text,
          finalInput: true,
          minCodepoints: minCodepoints,
        ).units;
        for (var n = 0; n < 300; n++) {
          final units = <String>[];
          var remainder = '';
          for (final fragment in _fragments(text, random)) {
            final split = kokoroSplitSentences(
              remainder + fragment,
              minCodepoints: minCodepoints,
            );
            units.addAll(split.units);
            remainder = split.remainder;
          }
          units.addAll(
            kokoroSplitSentences(
              remainder,
              finalInput: true,
              minCodepoints: minCodepoints,
            ).units,
          );
          runs++;
          expect(units, whole, reason: text);
        }
      }
    }
    expect(runs, _corpus.length * 600);
  });

  test('I1: KokoroTextInput gives the same units for any fragments', () async {
    final random = Random(2);
    for (final text in _corpus) {
      final whole = kokoroSplitSentences(text, finalInput: true).units;
      for (var n = 0; n < 40; n++) {
        final engine = _FakeKokoro();
        final input = engine.input(voice: 'v');
        final texts = _texts(input);
        for (final fragment in _fragments(text, random)) {
          input.add(fragment);
          // Sometimes let the reader run between fragments.
          if (random.nextInt(3) == 0) await pumpEventQueue(times: 2);
        }
        await input.close();
        expect(await texts, whole, reason: text);
      }
    }
  });

  test('when kokoroSplitMayChange is false, the split gives no units', () {
    const corpus = _corpus;
    final random = Random(14);
    var checked = 0;
    for (final text in corpus) {
      for (var cut = 0; cut <= text.length; cut++) {
        final remainder = kokoroSplitSentences(
          text.substring(0, cut),
        ).remainder;
        for (var n = 0; n < 8; n++) {
          final end = min(text.length, cut + 1 + random.nextInt(12));
          final added = text.substring(cut, end);
          if (kokoroSplitMayChange(remainder, added)) continue;
          checked++;
          expect(
            kokoroSplitSentences(remainder + added).units,
            isEmpty,
            reason: 'remainder: "$remainder", added: "$added"',
          );
        }
      }
    }
    expect(checked, greaterThan(100));
  });
}
