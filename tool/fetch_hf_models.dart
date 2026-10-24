// Downloads the model files from Hugging Face into example/assets/models
// (ADR 001 D5). Each download is pinned to the Hugging Face commit of its
// entry in native_artifacts/manifest.json and checked by SHA-256. A file that
// is already there with that SHA-256 is kept.
//
// Usage: dart run tool/fetch_hf_models.dart [<path> ...]
//
// Each <path> is below example/assets/models: a file, or a directory such as
// `futoSwipe`. With no <path>, the tool downloads every model (1.5 GB).
import 'dart:io';

import 'package:kiln/runtime.dart';

import 'hf/models.dart';

Future<void> main(List<String> arguments) async {
  final root = File.fromUri(Platform.script).parent.parent;
  final prefixes = [
    for (final argument in arguments)
      argument.replaceAll(r'\', '/').replaceFirst(RegExp(r'/$'), ''),
  ];
  bool selected(HfModel model) =>
      prefixes.isEmpty ||
      prefixes.any(
        (prefix) =>
            model.modelPath == prefix || model.modelPath.startsWith('$prefix/'),
      );

  final models = hfModels(await readManifest(root)).where(selected).toList();
  if (models.isEmpty) throw ArgumentError('No model matches $arguments');
  for (final model in models) {
    if (model.commit == null) {
      throw StateError(
        '${model.path} is not on Hugging Face yet. '
        'Run dart run tool/publish_models.dart.',
      );
    }
    final file = model.file(root);
    final path = await ensureRuntimeFile(
      RuntimeFile(
        name: file.uri.pathSegments.last,
        sha256: model.sha256,
        bytes: model.bytes,
        url: model.url,
      ),
      file.parent,
    );
    stdout.writeln('OK: ${path.path}');
  }
}
