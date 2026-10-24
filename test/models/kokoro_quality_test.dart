import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:fonnx/models/kokoro/kokoro.dart';
import 'package:fonnx/models/kokoro/kokoro_ffi.dart';
import 'package:fonnx/models/nemoAsr/nemo_asr.dart';
import 'package:fonnx/onnx/ort.dart';

// The original eight regression sentences (including the GB "were" / "wear"
// case), then a fixed stride through the reference sentences of 8 to 14
// words. Seams come at about 0.6, 1.8 and 4.2 s, so short sentences have the
// most seams per second of audio. No sentence is selected by WER.
//
// Parakeet TDT v3 transcribes. Whisper tiny made errors of its own at seams
// that a human does not hear: with it, the shipped policy added 1.6 to 2.7
// points; with Parakeet, 0.2 to 0.6 on the same 1,240 words.
//
// Word errors do not show clicks. A policy with no crossfade gets the same
// score as the shipped policy.
//
// The whole-sentence transcripts are in [_baselinePath]. They change only
// when the model, a voice, the reference phonemes, or the recognizer
// changes. Make them again with
// --dart-define=KOKORO_QUALITY_UPDATE=true.
const _regression = [1, 2, 3, 4, 14, 15, 16, 28];
const _strided = 80;
const _baselinePath = 'test/data/goldens/kokoro_quality_whole.json';
const _update = bool.fromEnvironment('KOKORO_QUALITY_UPDATE');

List<int> _corpus(List golden) {
  final pool = [
    for (var i = 0; i < golden.length; i++)
      if (!_regression.contains(i) &&
          _words((golden[i] as Map)['text'] as String).length >= 8 &&
          _words((golden[i] as Map)['text'] as String).length <= 14)
        i,
  ];
  return [
    ..._regression,
    for (var k = 0; k < _strided; k++) pool[k * pool.length ~/ _strided],
  ];
}

void main() {
  test(
    'chunked English speech does not regress WER by over one point',
    () async {
      const dir = 'example/assets/models/kokoro';
      final engine = await Kokoro.load(KokoroBundle.fromDirectory(dir));
      addTearDown(engine.dispose);
      final whole = _update
          ? createOrtSession('$dir/onnx/model_uint8.onnx')
          : null;
      addTearDown(() => whole?.release());
      final baselines = _update
          ? <String, Object?>{}
          : jsonDecode(File(_baselinePath).readAsStringSync())
                as Map<String, Object?>;
      final asr = NemoAsr.load(
        NemoAsrBundle.parakeetTdtV3('example/assets/models/nemoAsr'),
      );
      final results = <Map<String, Object?>>[];
      final regressions = <String>[];
      for (final dialect in ['us', 'gb']) {
        final voiceName = dialect == 'us' ? 'af_heart' : 'bf_emma';
        final voice = Float32List.view(
          File('$dir/voices/$voiceName.bin').readAsBytesSync().buffer,
        );
        final golden =
            jsonDecode(
                  File(
                    'test/data/goldens/misaki_en_$dialect.json',
                  ).readAsStringSync(),
                )
                as List;
        var referenceErrors = 0, streamedErrors = 0, words = 0;
        for (final index in _corpus(golden)) {
          final entry = golden[index] as Map;
          final text = entry['text'] as String;
          final ps = entry['phonemes_fallback'] as String;
          final key = '$voiceName\t$text';
          if (whole != null) {
            final reference = runKokoroFfi(
              whole,
              ids: kokoroPhonemesToIds(ps),
              voice: voice,
            );
            baselines[key] = {
              'phonemes': ps,
              'transcript': await asr.doInference(_pcm16(reference)),
            };
          }
          final saved = baselines[key] as Map?;
          expect(
            saved?['phonemes'],
            ps,
            reason:
                'Baseline for "$text" is missing or old. Run again with '
                '--dart-define=KOKORO_QUALITY_UPDATE=true.',
          );
          final baseline = saved!['transcript'] as String;
          final streamed = await engine.synthesize(
            text,
            voice: voiceName,
            normalize: false,
          );
          final hypothesis = await asr.doInference(_pcm16(streamed));
          final target = _words(text);
          final baseErrors = _distance(target, _words(baseline));
          final newErrors = _distance(target, _words(hypothesis));
          referenceErrors += baseErrors;
          streamedErrors += newErrors;
          words += target.length;
          results.add({
            'dialect': dialect,
            'text': text,
            'whole': baseline,
            'streamed': hypothesis,
            'wholeErrors': baseErrors,
            'streamedErrors': newErrors,
            'words': target.length,
          });
        }
        // ignore: avoid_print
        print(
          '$voiceName WER whole ${referenceErrors / words}, streamed ${streamedErrors / words} ($words words)',
        );
        File('build/kokoro/quality.json').writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(results),
        );
        if ((streamedErrors - referenceErrors) / words > .01) {
          regressions.add(
            '$voiceName: ${(streamedErrors - referenceErrors) / words}',
          );
        }
      }
      if (_update) {
        File(_baselinePath).writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(baselines)}\n',
        );
      }
      expect(regressions, isEmpty, reason: regressions.join('; '));
    },
    timeout: const Timeout(Duration(minutes: 5)),
    skip: const bool.fromEnvironment('KOKORO_RELEASE_QUALITY')
        ? false
        : 'Release gate: opt in with --dart-define=KOKORO_RELEASE_QUALITY=true (see ADR 002).',
  );
}

List<String> _words(String text) => text
    .toLowerCase()
    .replaceAll(RegExp("[^a-z0-9' ]"), ' ')
    .split(RegExp(r'\s+'))
    .where((s) => s.isNotEmpty)
    .toList();
int _distance(List<String> a, List<String> b) {
  var previous = List.generate(b.length + 1, (i) => i);
  for (var i = 0; i < a.length; i++) {
    final row = List.filled(b.length + 1, 0);
    row[0] = i + 1;
    for (var j = 0; j < b.length; j++) {
      row[j + 1] = math.min(
        math.min(row[j] + 1, previous[j + 1] + 1),
        previous[j] + (a[i] == b[j] ? 0 : 1),
      );
    }
    previous = row;
  }
  return previous.last;
}

Uint8List _pcm16(Float32List input) {
  final n = input.length * 2 ~/ 3;
  final result = ByteData(n * 2);
  for (var i = 0; i < n; i++) {
    final position = i * 1.5, first = (i * 1.5).floor();
    final next = math.min(first + 1, input.length - 1);
    final sample =
        input[first] + (input[next] - input[first]) * (position - first);
    result.setInt16(
      i * 2,
      (sample.clamp(-1, 1) * 32767).round(),
      Endian.little,
    );
  }
  return result.buffer.asUint8List();
}
