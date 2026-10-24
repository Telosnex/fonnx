import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:fonnx/models/kokoro/kokoro.dart';
import 'package:fonnx/models/kokoro/kokoro_ffi.dart';
import 'package:fonnx/models/kokoro/kokoro_stages_ffi.dart';
import 'package:fonnx/onnx/ort.dart';

const _dir = 'example/assets/models/kokoro';
KokoroBundle bundle({String? decoder}) => KokoroBundle(
  prosodyModel: '$_dir/onnx/stages/prosody.onnx',
  decoderModel: decoder ?? '$_dir/onnx/stages/decoder.onnx',
  spacyConfig: '$_dir/spacy/en_core_web_sm.json',
  spacyWeights: '$_dir/spacy/en_core_web_sm_tagger.bin',
  usGold: '$_dir/misaki/us_gold.json',
  usSilver: '$_dir/misaki/us_silver.json',
  gbGold: '$_dir/misaki/gb_gold.json',
  gbSilver: '$_dir/misaki/gb_silver.json',
  fallbackModel: '$_dir/misaki/g2p_fallback_en_us.onnx',
  fallbackConfig: '$_dir/misaki/g2p_fallback_en_us.json',
  voices: {
    'bf_emma': const KokoroVoice(
      path: '$_dir/voices/bf_emma.bin',
      language: KokoroLanguage.britishEnglish,
    ),
    'af_heart': const KokoroVoice(
      path: '$_dir/voices/af_heart.bin',
      language: KokoroLanguage.americanEnglish,
    ),
  },
);
void main() {
  test(
    'split uint8 models reproduce whole inference and accept partial frames',
    () {
      final whole = createOrtSession('$_dir/onnx/model_uint8.onnx');
      final first = createOrtSession('$_dir/onnx/stages/prosody.onnx');
      final second = createOrtSession('$_dir/onnx/stages/decoder.onnx');
      addTearDown(whole.release);
      addTearDown(first.release);
      addTearDown(second.release);
      final g =
          jsonDecode(
                File(
                  'test/data/goldens/kokoro_af_heart.json',
                ).readAsStringSync(),
              )
              as Map;
      final voice = Float32List.view(
        File('$_dir/voices/af_heart.bin').readAsBytesSync().buffer,
      );
      final ids = kokoroPhonemesToIds(g['phonemes'] as String);
      final style = kokoroStyleForLength(voice, ids.length);
      final p = runKokoroProsody(first, ids: ids, style: style);
      final all = runKokoroDecoder(second, p, style, 0, p.frames);
      final reference = runKokoroFfi(whole, ids: ids, voice: voice);
      expect(all.length, reference.length);
      var max = 0.0;
      for (var i = 0; i < all.length; i++) {
        final d = (all[i] - reference[i]).abs();
        if (d > max) max = d;
      }
      expect(max, lessThan(1e-4));
      expect(runKokoroDecoder(second, p, style, 0, 24).length, 24 * 600);
    },
  );

  test(
    'native stream runs off UI, joins audio, cancels and can be reused',
    () async {
      final engine = await Kokoro.load(bundle());
      addTearDown(engine.dispose);
      final timer = Stopwatch()..start();
      final pieces = <Float32List>[];
      var firstMs = 0, ticks = 0, count = 0;
      final pulse = Timer.periodic(
        const Duration(milliseconds: 5),
        (_) => ticks++,
      );
      try {
        await for (final c in engine.speak(
          'I read the book yesterday, and I will read it again tomorrow.',
          voice: 'af_heart',
        )) {
          if (count++ == 0) {
            firstMs = timer.elapsedMilliseconds;
            expect(c.text, isNotNull);
          } else {
            expect(c.text, isNull);
          }
          expect(c.sampleRate, 24000);
          pieces.add(c.samples);
        }
      } finally {
        pulse.cancel();
      }
      expect(count, greaterThan(1));
      expect(ticks, greaterThan(1));
      final wav = Float32List(pieces.fold(0, (n, p) => n + p.length));
      var offset = 0;
      for (final p in pieces) {
        wav.setAll(offset, p);
        offset += p.length;
      }
      File('build/kokoro/kokoro_streamed.wav').writeAsBytesSync(kokoroWav(wav));
      // ignore: avoid_print
      print(
        'stream: first ${firstMs}ms, total ${timer.elapsedMilliseconds}ms, '
        '${wav.length / 24000}s audio, $count chunks',
      );
      final stream = StreamIterator(
        engine.speak(
          'This should stop after the first chunk.',
          voice: 'af_heart',
        ),
      );
      expect(await stream.moveNext(), isTrue);
      await stream.cancel();
      final audio = await engine.synthesize('Hello again.', voice: 'af_heart');
      expect(audio, isNotEmpty);
      await Future.wait([engine.dispose(), engine.dispose()]);
      await expectLater(
        engine.synthesize('No session.', voice: 'af_heart'),
        throwsStateError,
      );
    },
  );

  test(
    'incremental text, explicit flush, empty input and validation',
    () async {
      final engine = await Kokoro.load(bundle());
      addTearDown(engine.dispose);
      final sink = engine.input(voice: 'af_heart');
      final texts = <String>[];
      final done = sink.audio.forEach((chunk) {
        if (chunk.text != null) texts.add(chunk.text!);
      });
      sink.add('Hel');
      sink.add('lo there. ');
      sink.add('No terminator');
      sink.flush();
      await sink.close();
      await done;
      expect(texts, ['Hello there.', 'No terminator']);
      final british = await engine.synthesize(
        'The colour of the water is blue.',
        voice: 'bf_emma',
      );
      expect(british, isNotEmpty);
      expect(await engine.synthesize('  ', voice: 'af_heart'), isEmpty);
      expect(() => engine.input(voice: 'not a voice'), throwsArgumentError);
      expect(
        () => engine.input(voice: 'af_heart', speed: double.nan),
        throwsArgumentError,
      );
      // Closing before listening does not wait for the audio.
      final early = engine.input(voice: 'af_heart')..add('Early bird.');
      await early.close().timeout(const Duration(seconds: 5));
      await early.close();
      expect(
        await early.audio
            .where((c) => c.text != null)
            .map((c) => c.text)
            .toList(),
        ['Early bird.'],
      );
      final pending = engine.input(voice: 'af_heart');
      expect(() => pending.add('a' * 65537), throwsStateError);
      final pendingDone = pending.audio.drain<void>();
      await pending.close();
      await pendingDone;
    },
  );

  test(
    'a sentence over the phoneme limit is one utterance; long text is fine',
    () async {
      final engine = await Kokoro.load(bundle());
      addTearDown(engine.dispose);
      final long = List.filled(
        12,
        'the coach keeps talking about the application and the interview',
      ).join(', ');
      final chunks = await engine
          .speak('$long. Short one.', voice: 'af_heart')
          .toList();
      expect(chunks.map((c) => c.utteranceId).toSet(), hasLength(2));
      expect(chunks.where((c) => c.isFinal), hasLength(2));
      expect(chunks.where((c) => c.text != null).map((c) => c.text), [
        '$long.',
        'Short one.',
      ]);
      expect(chunks.first.phonemes!.runes.length, greaterThan(510));
      // Over 64K characters in one call is fine when it has sentence ends.
      final stream = StreamIterator(
        engine.speak(List.filled(10000, 'Go on.').join(' '), voice: 'af_heart'),
      );
      expect(await stream.moveNext(), isTrue);
      await stream.cancel();
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('queued cancellation does not wait for a paused predecessor', () async {
    final engine = await Kokoro.load(bundle());
    addTearDown(engine.dispose);
    final active = StreamIterator(
      engine.speak(
        'This is a long enough sentence to produce several audio chunks.',
        voice: 'af_heart',
      ),
    );
    expect(await active.moveNext(), isTrue);
    final queued = StreamIterator(
      engine.speak('Queued request.', voice: 'af_heart'),
    );
    final waiting = queued.moveNext();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await queued.cancel().timeout(const Duration(seconds: 2));
    expect(await waiting, isFalse);
    await active.cancel();
    expect(
      await engine.synthesize('Still usable.', voice: 'af_heart'),
      isNotEmpty,
    );
  });

  test('load failure releases partially initialized worker', () async {
    await expectLater(
      Kokoro.load(bundle(decoder: 'missing.onnx')),
      throwsStateError,
    );
  });
}
