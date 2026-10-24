/// Tests the web runtime files in lib/web/ (kiln ADR 002 D10, D13). The kiln
/// release workflow runs it after `kiln:web install-dev` of the files that
/// tool/kiln/build_web.dart built.
///
/// Locally, after `dart run kiln:web install-dev`:
///
///     dart run tool/kiln/test_web.dart
library;

import 'dart:io';

/// The models of the web tests. The release workflow caches the .onnx files
/// in example/assets/models; a change to this list changes its cache key.
const _models = [
  'futoSwipe',
  'keywordSpotter',
  'magika',
  'miniLmL6V2',
  'minishLab/potion8m.onnx',
  'msmarcoMiniLmL6V3',
  'nemoAsr/fastconformer_ctc_multilingual_int8.onnx',
  'pyannote',
  'senseVoice',
  'sileroVad',
  'whisper',
];

Future<void> main() async {
  final root = Directory.fromUri(Platform.script.resolve('../..')).path;
  final dart = Platform.resolvedExecutable;
  await _run(root, dart, ['run', 'tool/fetch_hf_models.dart', ..._models]);
  await _run(root, 'node', ['tool/test_web_runtime.mjs']);
  await _run(root, dart, [
    'test',
    '-p',
    'chrome',
    '-c',
    'dart2js,dart2wasm',
    'test/web_runtime_test.dart',
    'test/deterministic_operation_corpus_test.dart',
  ]);
}

Future<void> _run(String root, String executable, List<String> args) async {
  stdout.writeln('\$ ${[executable, ...args].join(' ')}');
  final process = await Process.start(
    executable,
    args,
    workingDirectory: root,
    mode: ProcessStartMode.inheritStdio,
  );
  final code = await process.exitCode;
  if (code != 0) {
    stderr.writeln('Failed with exit code $code.');
    exit(code);
  }
}
