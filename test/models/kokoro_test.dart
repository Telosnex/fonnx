import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:fonnx/models/kokoro/kokoro_ffi.dart';
import 'package:fonnx/models/kokoro/misaki/misaki.dart';
import 'package:fonnx/models/kokoro/misaki/misaki_fallback_ffi.dart';
import 'package:fonnx/onnx/ort.dart';

const _dir = 'example/assets/models/kokoro';

void main() {
  final golden =
      jsonDecode(
            File('test/data/goldens/kokoro_af_heart.json').readAsStringSync(),
          )
          as Map<String, dynamic>;
  final voice = Float32List.view(
    File('$_dir/voices/af_heart.bin').readAsBytesSync().buffer,
  );

  test('Kokoro phoneme tokenizer matches upstream tokenizer.json', () {
    final ids = kokoroPhonemesToIds(golden['phonemes'] as String);
    expect([0, ...ids, 0], orderedEquals(golden['input_ids'] as List));
  });

  test('Kokoro fp32 matches Python onnxruntime reference', () {
    final session = createOrtSession('$_dir/onnx/model.onnx');
    addTearDown(session.release);
    final ids = kokoroPhonemesToIds(golden['phonemes'] as String);

    final sw = Stopwatch()..start();
    final audio = runKokoroFfi(session, ids: ids, voice: voice);
    sw.stop();

    expect(audio.length, golden['samples']);
    final head = (golden['head'] as List).cast<num>();
    for (var i = 0; i < head.length; i++) {
      expect(audio[i * 20], closeTo(head[i].toDouble(), 2e-3), reason: '$i');
    }
    var sumSq = 0.0;
    for (final s in audio) {
      sumSq += s * s;
    }
    final rms = math.sqrt(sumSq / audio.length);
    expect(rms, closeTo((golden['rms'] as num).toDouble(), 1e-3));

    final seconds = audio.length / kokoroSampleRate;
    // ignore: avoid_print
    print(
      'fp32: ${seconds.toStringAsFixed(2)}s audio in '
      '${sw.elapsedMilliseconds}ms (first run, RTF '
      '${(sw.elapsedMilliseconds / 1000 / seconds).toStringAsFixed(3)})',
    );
    File('build/kokoro/kokoro_af_heart_fp32.wav')
      ..createSync(recursive: true)
      ..writeAsBytesSync(kokoroWav(audio));
  });

  // model_uint8 rather than model_quantized/model_q8f16: on the pinned ORT
  // 1.27 the dynamically quantized graphs run ~4x slower than fp32 (ConvInteger
  // and friends lack fast kernels there; ORT 1.31 fixes it). uint8 is fast on
  // both, and is the base Moonshine Voice repacks for Raspberry Pi.
  test('Kokoro uint8 runs and times warm inference', () {
    final session = createOrtSession('$_dir/onnx/model_uint8.onnx');
    addTearDown(session.release);
    final ids = kokoroPhonemesToIds(golden['phonemes'] as String);
    runKokoroFfi(session, ids: ids, voice: voice);
    final sw = Stopwatch()..start();
    final audio = runKokoroFfi(session, ids: ids, voice: voice);
    sw.stop();
    final seconds = audio.length / kokoroSampleRate;
    expect(seconds, greaterThan(5));
    // ignore: avoid_print
    print(
      'uint8: ${seconds.toStringAsFixed(2)}s audio in '
      '${sw.elapsedMilliseconds}ms warm (RTF '
      '${(sw.elapsedMilliseconds / 1000 / seconds).toStringAsFixed(3)})',
    );
    File('build/kokoro/kokoro_af_heart_uint8.wav')
      ..createSync(recursive: true)
      ..writeAsBytesSync(kokoroWav(audio));
  });

  test('Text to speech entirely in Dart: misaki + Kokoro', () {
    final fallbackSession = createOrtSession(
      '$_dir/misaki/g2p_fallback_en_us.onnx',
    );
    addTearDown(fallbackSession.release);
    final misaki = Misaki.load(
      gold: jsonDecode(File('$_dir/misaki/us_gold.json').readAsStringSync()),
      silver: jsonDecode(
        File('$_dir/misaki/us_silver.json').readAsStringSync(),
      ),
      spacyConfigJson: File(
        '$_dir/spacy/en_core_web_sm.json',
      ).readAsStringSync(),
      spacyWeights: File(
        '$_dir/spacy/en_core_web_sm_tagger.bin',
      ).readAsBytesSync(),
      fallback: MisakiFallbackFfi(
        fallbackSession,
        File('$_dir/misaki/g2p_fallback_en_us.json').readAsStringSync(),
      ).call,
      unk: '',
    );
    // Same text as the golden: Dart phonemes must give the same ids.
    expect([
      0,
      ...kokoroPhonemesToIds(misaki.phonemize(golden['text'] as String)),
      0,
    ], orderedEquals(golden['input_ids'] as List));

    final session = createOrtSession('$_dir/onnx/model_uint8.onnx');
    addTearDown(session.release);
    const text =
        'I read the book yesterday, and I will read it again tomorrow. '
        'Mr. Darcy paid \$5.99 on March 5th, 2024, for 3 tickets.';
    final sw = Stopwatch()..start();
    final phonemes = misaki.phonemize(text);
    final g2pMs = sw.elapsedMilliseconds;
    final audio = runKokoroFfi(
      session,
      ids: kokoroPhonemesToIds(phonemes),
      voice: voice,
    );
    // ignore: avoid_print
    print(
      '$phonemes\ng2p ${g2pMs}ms, total ${sw.elapsedMilliseconds}ms '
      'for ${(audio.length / kokoroSampleRate).toStringAsFixed(2)}s',
    );
    File('build/kokoro/kokoro_text_to_speech.wav')
      ..createSync(recursive: true)
      ..writeAsBytesSync(kokoroWav(audio));
  });
}
