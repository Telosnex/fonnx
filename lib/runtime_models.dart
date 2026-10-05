/// Downloadable ONNX models published by fonnx.
///
/// The keys in [runtimeModelNamesByPath] are paths below
/// `example/assets/models`. The values are the plain file names used in the
/// runtime release. Models are runtime downloads; they are not app assets.
library;

import 'dart:io';

import 'package:native_prebuilt/runtime.dart';

import 'src/native_prebuilt.g.dart';
export 'src/native_prebuilt.g.dart' show nativePrebuiltRuntimeFiles;

/// Maps each model's source path to its stable runtime-release file name.
///
/// Runtime releases require unique plain file names. In particular, the two
/// FUTO Swipe `model_fp32.onnx` files therefore have distinct release names.
const runtimeModelNamesByPath = <String, String>{
  'bpe_decoder.onnx': 'bpe_decoder.onnx',
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
  'magika/magika.onnx': 'magika.onnx',
  'miniLmL6V2/miniLmL6V2.onnx': 'miniLmL6V2.onnx',
  'minishLab/potion32m.onnx': 'potion32m.onnx',
  'minishLab/potion8m.onnx': 'potion8m.onnx',
  'msmarcoMiniLmL6V3/msmarcoMiniLmL6V3.onnx': 'msmarcoMiniLmL6V3.onnx',
  'pyannote/pyannote_seg3.onnx': 'pyannote_seg3.onnx',
  'sileroVad/silero_vad_v6.2.1.onnx': 'silero_vad_v6.2.1.onnx',
  'whisper/whisper_tiny.onnx': 'whisper_tiny.onnx',
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
  Map<String, RuntimeFile> runtimeFiles = nativePrebuiltRuntimeFiles,
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
/// `native_prebuilt/runtime.dart` (ADR 005 D13).
Future<File> ensureFonnxRuntimeModel(
  String modelPath,
  Directory directory, {
  Map<String, RuntimeFile> runtimeFiles = nativePrebuiltRuntimeFiles,
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
