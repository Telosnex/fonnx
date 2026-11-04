// Times each model's inference on fixed inputs, for comparing ONNX Runtime
// versions (see onnx_runtime/updating.md). Prints one JSON line per model:
// the first call (which includes loading the model) and the median, p10 and
// p90 of the runs after warm-up.
//
//   dart run test/bench/ort_bench.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fonnx/tokenizers/potion_32m_tokenizer.dart';
import 'package:fonnx/models/keyword_spotter/keyword_spotter.dart';
import 'package:fonnx/models/magika/magika_native.dart';
import 'package:fonnx/models/minilml6v2/mini_lm_l6_v2.dart';
import 'package:fonnx/models/minilml6v2/mini_lm_l6_v2_native.dart';
import 'package:fonnx/models/minishLab/minish_lab.dart';
import 'package:fonnx/models/minishLab/minish_lab_native.dart';
import 'package:fonnx/models/msmarcoMiniLmL6V3/msmarco_mini_lm_l6_v3.dart';
import 'package:fonnx/models/msmarcoMiniLmL6V3/msmarco_mini_lm_l6_v3_native.dart';
import 'package:fonnx/models/nemoAsr/nemo_asr.dart';
import 'package:fonnx/models/nemoAsr/nemo_asr_native.dart';
import 'package:fonnx/models/pyannote/pyannote.dart';
import 'package:fonnx/models/pyannote/pyannote_native.dart';
import 'package:fonnx/models/senseVoice/sense_voice.dart';
import 'package:fonnx/models/senseVoice/sense_voice_native.dart';
import 'package:fonnx/models/sileroVad/silero_vad.dart';
import 'package:fonnx/models/whisper/whisper.dart';
import 'package:fonnx/models/whisper/whisper_native.dart';

const m = 'example/assets/models';
final rain = File('test/data/audio_sample_ac1_ar16000.pcm').readAsBytesSync();
final talk = File('test/data/talkovergpt.pcm').readAsBytesSync();
const text =
    'I looked through the three reports you sent this morning, and the main '
    'difference is that the second one counts returns as revenue, which makes '
    'its totals twelve percent higher than the others.';

Future<void> bench(
  String name,
  Future<Object?> Function() run, {
  int warmup = 3,
  int runs = 20,
}) async {
  // The first call includes session creation; report it apart.
  final cold = Stopwatch()..start();
  await run();
  final coldMs = cold.elapsedMicroseconds / 1000;
  for (var i = 1; i < warmup; i++) {
    await run();
  }
  final times = <double>[];
  for (var i = 0; i < runs; i++) {
    final s = Stopwatch()..start();
    await run();
    times.add(s.elapsedMicroseconds / 1000);
  }
  times.sort();
  double q(double p) => times[((times.length - 1) * p).round()];
  print(
    jsonEncode({
      'model': name,
      'first_ms': coldMs,
      'median_ms': q(.5),
      'p10_ms': q(.1),
      'p90_ms': q(.9),
      'runs': runs,
    }),
  );
}

Future<void> main() async {
  final minilm = MiniLmL6V2Native('$m/miniLmL6V2/miniLmL6V2.onnx');
  final minilmTokens = MiniLmL6V2.tokenizer.tokenize(text).first.tokens;
  await bench('MiniLM-L6-v2', () => minilm.getEmbeddingAsVector(minilmTokens));

  final msmarco = MsmarcoMiniLmL6V3Native(
    '$m/msmarcoMiniLmL6V3/msmarcoMiniLmL6V3.onnx',
  );
  final msTokens = MsmarcoMiniLmL6V3.tokenizer.tokenize(text).first.tokens;
  await bench(
    'msmarco-MiniLM-L6-v3',
    () => msmarco.getEmbeddingAsVector(msTokens),
  );

  final p8 = MinishLabNative('$m/minishLab/potion8m.onnx');
  final p8t = MinishLab.potion8mTokenizer.tokenize(text).first.tokens;
  await bench('potion-8M', () => p8.getEmbeddingAsVector(p8t));

  final p32 = MinishLabNative('$m/minishLab/potion32m.onnx');
  final p32t = potion32mTokenizer.tokenize(text).first.tokens;
  await bench('potion-32M', () => p32.getEmbeddingAsVector(p32t));

  final magika = MagikaNative('$m/magika/magika.onnx');
  final asm = File('test/data/magika/basic/code.c').readAsBytesSync();
  await bench('Magika', () => magika.getType(asm));

  final vad = SileroVad.load('$m/sileroVad/silero_vad_v6.2.1.onnx');
  final chunk = Uint8List.sublistView(rain, 0, 1024); // 512 samples, 32 ms.
  await bench(
    'Silero VAD (32 ms chunk)',
    () => vad.doInference(chunk),
    runs: 100,
  );

  final pyannote = PyannoteNative('$m/pyannote/pyannote_seg3.onnx');
  final talkF = Pyannote.int16PcmBytesToFloat32(talk);
  await bench(
    'Pyannote seg3 (${talk.length ~/ 32000}s)',
    () => pyannote.process(talkF),
    runs: 10,
  );

  final whisper = WhisperNative(WhisperBundle.tiny('$m/whisper'));
  await bench(
    'Whisper tiny (rain, ${rain.length ~/ 32000}s)',
    () => whisper.doInference(rain),
    runs: 10,
  );

  final sense = SenseVoiceNative(SenseVoiceBundle.inDirectory('$m/senseVoice'));
  await bench('SenseVoice (rain)', () => sense.doInference(rain), runs: 10);

  final nemo = NemoAsrNative(
    NemoAsrBundle.fastConformerCtcMultilingual('$m/nemoAsr'),
  );
  await bench(
    'NeMo FastConformer CTC (rain)',
    () => nemo.doInference(rain),
    runs: 10,
  );

  final kws = await KeywordSpotter.load(
    bundle: KeywordSpotterBundle.gigaSpeech3m('$m/keywordSpotter'),
    keywords: const [KeywordPhrase('rain in Spain')],
  );
  final sub = kws.detections.listen((_) {});
  await bench('Keyword spotter (rain, streamed)', () async {
    await kws.reset();
    for (var o = 0; o < rain.length; o += 3200) {
      await kws.acceptPcm16(
        rain.sublist(o, o + 3200 < rain.length ? o + 3200 : rain.length),
      );
    }
    await kws.finish();
    return null;
  }, runs: 10);
  await sub.cancel();
  await kws.close();
  exit(0);
}
