@TestOn('browser')
@Timeout(Duration(minutes: 4))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:fonnx/fonnx.dart';

import 'kokoro_web_golden.dart';

/// Kokoro through its public API in the browser, on the web runtime files in
/// lib/web/. Build them first:
///
///     dart run tool/kiln/build_web.dart --out /tmp/fonnx_web
///     dart run kiln:web install-dev --from /tmp/fonnx_web
///
/// The test server serves test/ at the root, so the bundle comes from the
/// test/web_models link to example/assets/models (tool/kokoro/prepare_bundle.dart).
///
///     dart test -p chrome test/models/kokoro_web_test.dart
void main() {
  late Kokoro kokoro;
  var loaded = false;
  late List<Map<String, dynamic>> golden;

  setUpAll(() async {
    FonnxWeb.runtimeUri = Uri.parse('/packages/fonnx/web/');
    golden = (jsonDecode(await _text('/data/goldens/kokoro_web.json')) as List)
        .cast<Map<String, dynamic>>();
    final timer = Stopwatch()..start();
    kokoro = await Kokoro.load(
      KokoroBundle.fromDirectory('/web_models/kokoro'),
      policy: kokoroWebPolicy,
    );
    loaded = true;
    // ignore: avoid_print
    print('crossOriginIsolated: ${_isolated.toDart}');
    // ignore: avoid_print
    print('load ${timer.elapsedMilliseconds} ms');
  });
  tearDownAll(() async {
    if (loaded) await kokoro.dispose();
  });

  test('phonemes and audio match native', () async {
    for (final want in golden) {
      final timer = Stopwatch()..start();
      int? firstMs;
      final chunks = <KokoroChunk>[];
      await for (final c in kokoro.speak(
        want['text'] as String,
        voice: want['voice'] as String,
      )) {
        firstMs ??= timer.elapsedMilliseconds;
        chunks.add(c);
      }
      final audio = Float32List.fromList([
        for (final c in chunks) ...c.samples,
      ]);
      final seconds = audio.length / 24000;
      // ignore: avoid_print
      print(
        '${want['voice']}: first audio $firstMs ms, '
        '${timer.elapsedMilliseconds} ms for ${seconds.toStringAsFixed(2)} s, '
        '${chunks.length} chunks',
      );
      expect(chunks.first.phonemes, want['phonemes'], reason: want['text']);
      expect(chunks.first.text, want['text']);
      expect(chunks.last.isFinal, isTrue);
      expect(chunks.length, greaterThan(1));
      expect(chunks.map((c) => c.utteranceId).toSet(), hasLength(1));
      // With a fixed span plan, web decodes the same spans as native. ORT Web
      // differs from native only in float rounding.
      expect(audio.length, want['samples'], reason: want['text']);
      final correlation = kokoroCorrelation(kokoroEnvelope(audio), [
        for (final v in want['envelope'] as List) (v as num).toDouble(),
      ]);
      // ignore: avoid_print
      print('  envelope correlation ${correlation.toStringAsFixed(3)}');
      expect(correlation, greaterThan(0.98), reason: want['text']);
      expect(audio.every((v) => v.isFinite && v.abs() <= 1.5), isTrue);
    }
  });

  test('input streams fragments, and cancel then reuse works', () async {
    final input = kokoro.input(voice: 'af_heart');
    final audio = input.audio.toList();
    input
      ..add('Hello there. ')
      ..add('How are')
      ..add(' you today?');
    await input.close();
    final chunks = await audio;
    expect(chunks.map((c) => c.utteranceId).toSet(), hasLength(2));
    expect(chunks.where((c) => c.text != null).map((c) => c.text), [
      'Hello there.',
      'How are you today?',
    ]);

    final stream = StreamIterator(
      kokoro.speak(
        'This should stop after the first chunk, long before the end.',
        voice: 'af_heart',
      ),
    );
    expect(await stream.moveNext(), isTrue);
    await stream.cancel();
    expect(
      await kokoro.synthesize('Hello again.', voice: 'bf_emma'),
      isNotEmpty,
    );
  });

  test('the page stays responsive while Kokoro works', () async {
    var ticks = 0;
    final pulse = Timer.periodic(
      const Duration(milliseconds: 10),
      (_) => ticks++,
    );
    final timer = Stopwatch()..start();
    try {
      await kokoro.synthesize(
        'The phonemizer and both model stages run in the Worker, not here.',
        voice: 'af_heart',
      );
    } finally {
      pulse.cancel();
    }
    // At least half the 10 ms ticks fire; a blocked thread fires almost none.
    expect(ticks, greaterThan(timer.elapsedMilliseconds ~/ 20));
  });

  test('dispose ends the engine', () async {
    final other = await Kokoro.load(
      KokoroBundle.fromDirectory(
        '/web_models/kokoro',
        voiceNames: ['af_heart'],
      ),
    );
    expect(await other.synthesize('One.', voice: 'af_heart'), isNotEmpty);
    await Future.wait([other.dispose(), other.dispose()]);
    await expectLater(
      other.synthesize('Two.', voice: 'af_heart'),
      throwsStateError,
    );
    // The shared Worker still serves the first engine.
    expect(await kokoro.synthesize('Three.', voice: 'af_heart'), isNotEmpty);
  });

  test('a missing model fails the load', () async {
    final bundle = KokoroBundle.fromDirectory('/web_models/kokoro');
    await expectLater(
      Kokoro.load(
        KokoroBundle(
          prosodyModel: bundle.prosodyModel,
          decoderModel: '/web_models/kokoro/missing.onnx',
          spacyConfig: bundle.spacyConfig,
          spacyWeights: bundle.spacyWeights,
          usGold: bundle.usGold,
          usSilver: bundle.usSilver,
          gbGold: bundle.gbGold,
          gbSilver: bundle.gbSilver,
          fallbackModel: bundle.fallbackModel,
          fallbackConfig: bundle.fallbackConfig,
          voices: bundle.voices,
        ),
      ),
      throwsA(predicate((e) => '$e'.contains('HTTP 404'))),
    );
  });
}

Future<String> _text(String path) async {
  final response = await _fetch(path.toJS).toDart;
  if (!response.ok) fail('GET $path: HTTP ${response.status}');
  return (await response.text().toDart).toDart;
}

@JS('crossOriginIsolated')
external JSBoolean get _isolated;

@JS('fetch')
external JSPromise<_Response> _fetch(JSString url);

extension type _Response(JSObject _) implements JSObject {
  external bool get ok;
  external int get status;
  external JSPromise<JSString> text();
}
