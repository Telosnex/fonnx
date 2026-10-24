/// Downloadable ONNX models published by fonnx.
///
/// The keys in [runtimeModelNamesByPath] are paths below
/// `example/assets/models`. The values are the plain file names used in the
/// runtime catalog. Models are runtime downloads; they are not app assets.
library;

import 'dart:io';

import 'package:kiln/runtime.dart';

import 'src/kiln.g.dart';
export 'src/kiln.g.dart' show prebuiltRuntimeFiles;

/// Maps each model's source path to its stable runtime-release file name.
///
/// Runtime releases require unique plain file names. In particular, the two
/// FUTO Swipe `model_fp32.onnx` files therefore have distinct release names.
const runtimeModelNamesByPath = <String, String>{
  'futoSwipe/honorable_sturgeon/model_fp32.onnx':
      'futo_swipe_encoder_honorable_sturgeon.onnx',
  'futoSwipe/hungry_jellyfish/context_lm.onnx':
      'futo_swipe_context_lm_hungry_jellyfish.onnx',
  'futoSwipe/hungry_jellyfish/get_embeddings.onnx':
      'futo_swipe_embeddings_hungry_jellyfish.onnx',
  'futoSwipe/magic_macaw/model_fp32.onnx':
      'futo_swipe_decoder_magic_macaw.onnx',
  'keywordSpotter/decoder-epoch-12-avg-2-chunk-16-left-64.int8.onnx':
      'decoder-epoch-12-avg-2-chunk-16-left-64.int8.onnx',
  'keywordSpotter/encoder-epoch-12-avg-2-chunk-16-left-64.int8.onnx':
      'encoder-epoch-12-avg-2-chunk-16-left-64.int8.onnx',
  'keywordSpotter/joiner-epoch-12-avg-2-chunk-16-left-64.int8.onnx':
      'joiner-epoch-12-avg-2-chunk-16-left-64.int8.onnx',
  'kokoro/onnx/stages/prosody.onnx': 'kokoro_prosody.onnx',
  'kokoro/onnx/stages/decoder.onnx': 'kokoro_decoder.onnx',
  'kokoro/spacy/en_core_web_sm.json': 'kokoro_spacy_en_core_web_sm.json',
  'kokoro/spacy/en_core_web_sm_tagger.bin':
      'kokoro_spacy_en_core_web_sm_tagger.bin',
  'kokoro/misaki/us_gold.json': 'kokoro_misaki_us_gold.json',
  'kokoro/misaki/us_silver.json': 'kokoro_misaki_us_silver.json',
  'kokoro/misaki/gb_gold.json': 'kokoro_misaki_gb_gold.json',
  'kokoro/misaki/gb_silver.json': 'kokoro_misaki_gb_silver.json',
  'kokoro/misaki/g2p_fallback_en_us.onnx': 'kokoro_g2p_fallback_en_us.onnx',
  'kokoro/misaki/g2p_fallback_en_us.json': 'kokoro_g2p_fallback_en_us.json',
  'kokoro/voices/af_alloy.bin': 'kokoro_voice_af_alloy.bin',
  'kokoro/voices/af_aoede.bin': 'kokoro_voice_af_aoede.bin',
  'kokoro/voices/af_bella.bin': 'kokoro_voice_af_bella.bin',
  'kokoro/voices/af_heart.bin': 'kokoro_voice_af_heart.bin',
  'kokoro/voices/af_jessica.bin': 'kokoro_voice_af_jessica.bin',
  'kokoro/voices/af_kore.bin': 'kokoro_voice_af_kore.bin',
  'kokoro/voices/af_nicole.bin': 'kokoro_voice_af_nicole.bin',
  'kokoro/voices/af_nova.bin': 'kokoro_voice_af_nova.bin',
  'kokoro/voices/af_river.bin': 'kokoro_voice_af_river.bin',
  'kokoro/voices/af_sarah.bin': 'kokoro_voice_af_sarah.bin',
  'kokoro/voices/af_sky.bin': 'kokoro_voice_af_sky.bin',
  'kokoro/voices/am_adam.bin': 'kokoro_voice_am_adam.bin',
  'kokoro/voices/am_echo.bin': 'kokoro_voice_am_echo.bin',
  'kokoro/voices/am_eric.bin': 'kokoro_voice_am_eric.bin',
  'kokoro/voices/am_fenrir.bin': 'kokoro_voice_am_fenrir.bin',
  'kokoro/voices/am_liam.bin': 'kokoro_voice_am_liam.bin',
  'kokoro/voices/am_michael.bin': 'kokoro_voice_am_michael.bin',
  'kokoro/voices/am_onyx.bin': 'kokoro_voice_am_onyx.bin',
  'kokoro/voices/am_puck.bin': 'kokoro_voice_am_puck.bin',
  'kokoro/voices/am_santa.bin': 'kokoro_voice_am_santa.bin',
  'kokoro/voices/bf_alice.bin': 'kokoro_voice_bf_alice.bin',
  'kokoro/voices/bf_emma.bin': 'kokoro_voice_bf_emma.bin',
  'kokoro/voices/bf_isabella.bin': 'kokoro_voice_bf_isabella.bin',
  'kokoro/voices/bf_lily.bin': 'kokoro_voice_bf_lily.bin',
  'kokoro/voices/bm_daniel.bin': 'kokoro_voice_bm_daniel.bin',
  'kokoro/voices/bm_fable.bin': 'kokoro_voice_bm_fable.bin',
  'kokoro/voices/bm_george.bin': 'kokoro_voice_bm_george.bin',
  'kokoro/voices/bm_lewis.bin': 'kokoro_voice_bm_lewis.bin',
  'magika/magika.onnx': 'magika.onnx',
  'miniLmL6V2/miniLmL6V2.onnx': 'miniLmL6V2.onnx',
  'minishLab/potion32m.onnx': 'potion32m.onnx',
  'minishLab/potion8m.onnx': 'potion8m.onnx',
  'msmarcoMiniLmL6V3/msmarcoMiniLmL6V3.onnx': 'msmarcoMiniLmL6V3.onnx',
  'nemoAsr/fastconformer_ctc_multilingual_int8.onnx':
      'fastconformer_ctc_multilingual_int8.onnx',
  'nemoAsr/parakeet_tdt_v3_decoder_int8.onnx':
      'parakeet_tdt_v3_decoder_int8.onnx',
  'nemoAsr/parakeet_tdt_v3_encoder_int8.onnx':
      'parakeet_tdt_v3_encoder_int8.onnx',
  'nemoAsr/parakeet_tdt_v3_joiner_int8.onnx':
      'parakeet_tdt_v3_joiner_int8.onnx',
  'pyannote/pyannote_seg3.onnx': 'pyannote_seg3.onnx',
  'senseVoice/sense_voice_small_int8.onnx': 'sense_voice_small_int8.onnx',
  'senseVoice/sense_voice_small_tokens.txt': 'sense_voice_small_tokens.txt',
  'sileroVad/silero_vad_v6.2.1.onnx': 'silero_vad_v6.2.1.onnx',
  'whisper/whisper_tiny_decoder.onnx': 'whisper_tiny_decoder.onnx',
  'whisper/whisper_tiny_encoder.onnx': 'whisper_tiny_encoder.onnx',
};

/// Maps a runtime-release file name back to its model source path.
final Map<String, String> runtimeModelPathsByName = Map.unmodifiable({
  for (final entry in runtimeModelNamesByPath.entries) entry.value: entry.key,
});

/// Returns the stable runtime-release file name for [modelPath].
///
/// [modelPath] may be relative to `example/assets/models`, or it may include
/// that prefix. Both `/` and `\\` separators are accepted.
String runtimeModelName(String modelPath) {
  final normalized = _normalizeModelPath(modelPath);
  return runtimeModelNamesByPath[normalized] ??
      (throw ArgumentError.value(modelPath, 'modelPath', 'Unknown model'));
}

/// Returns the path below `example/assets/models` for [releaseName].
String runtimeModelPath(String releaseName) {
  return runtimeModelPathsByName[releaseName] ??
      (throw ArgumentError.value(
        releaseName,
        'releaseName',
        'Unknown runtime model',
      ));
}

/// Finds [modelPath] in the published runtime-file catalog.
RuntimeFile runtimeModelFile(
  String modelPath, [
  Map<String, RuntimeFile> runtimeFiles = prebuiltRuntimeFiles,
]) {
  final name = runtimeModelName(modelPath);
  final file = runtimeFiles[name];
  if (file == null) {
    throw StateError('The runtime release has no fonnx model named $name.');
  }
  if (file.name != name) {
    throw StateError(
      'Runtime model catalog key $name describes ${file.name} instead.',
    );
  }
  return file;
}

/// Downloads [modelPath] into [directory], verifies its pinned SHA-256, and
/// returns the local file.
///
/// An already downloaded file is reused only after it passes the same check.
/// The atomic download and verification are provided by
/// `kiln/runtime.dart` (kiln ADR 001 D13).
Future<File> ensureFonnxRuntimeModel(
  String modelPath,
  Directory directory, {
  Map<String, RuntimeFile> runtimeFiles = prebuiltRuntimeFiles,
  HttpClient? client,
  void Function(int received, int? total)? onProgress,
}) {
  return ensureRuntimeFile(
    runtimeModelFile(modelPath, runtimeFiles),
    directory,
    client: client,
    onProgress: onProgress,
  );
}

String _normalizeModelPath(String path) {
  var normalized = path.replaceAll('\\', '/');
  while (normalized.startsWith('./')) {
    normalized = normalized.substring(2);
  }
  const prefix = 'example/assets/models/';
  if (normalized.startsWith(prefix)) {
    normalized = normalized.substring(prefix.length);
  }
  return normalized;
}
