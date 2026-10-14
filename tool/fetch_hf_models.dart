// Downloads the model files that are on Hugging Face and not in Git into
// example/assets/models, pinned to a Hugging Face commit and checked by
// SHA-256. A file that is already there with that SHA-256 is kept.
//
// Usage: dart run tool/fetch_hf_models.dart
import 'dart:io';

import 'package:native_prebuilt/runtime.dart';

/// The commit of huggingface.co/telosnex/fonnx that has these files.
const _commit = 'bbecfb3bf170f508901dba5ae70afb482a3d65ca';

/// Directory under example/assets/models, and the file in it.
const _models = [
  (
    'nemoAsr',
    'fastconformer_ctc_multilingual_int8.onnx',
    'e3ea888bcc90cafdeeedeea26f6e8ca2186d8af7939236e0eb246206f5098c00',
    132445134,
  ),
];

Future<void> main() async {
  final root = File.fromUri(Platform.script).parent.parent;
  for (final (directory, name, sha256, bytes) in _models) {
    final file = await ensureRuntimeFile(
      RuntimeFile(
        name: name,
        sha256: sha256,
        bytes: bytes,
        url: 'https://huggingface.co/telosnex/fonnx/resolve/$_commit/$name',
      ),
      Directory('${root.path}/example/assets/models/$directory'),
    );
    stdout.writeln('OK: ${file.path}');
  }
}
