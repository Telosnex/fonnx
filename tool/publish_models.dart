// Uploads the model files to Hugging Face and writes the runtime catalog
// (ADR 001 D1, D3).
//
// Usage: dart run tool/publish_models.dart [--dry-run]
//
// To add or change a model, put the file in example/assets/models, and add
// its entry to the models section of native_artifacts/manifest.json without a
// commit. This tool then:
// 1. Checks each model that has a commit against Hugging Face.
// 2. Checks each model without a commit against its local file, and uploads
//    those files, the model card (tool/hf/README.md) and the FUTO license in
//    one Hugging Face commit with `hf upload`. It records the commit.
// 3. Writes the runtimeFiles section of native_artifacts/prebuilt.json and
//    lib/src/native_prebuilt.g.dart from the manifest.
//
// --dry-run does steps 1 and 2 without the upload, and writes nothing.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:native_prebuilt/native_prebuilt.dart';

import 'hf/models.dart';

/// Files next to the models on Hugging Face: their path in this package.
const _repositoryFiles = {
  'README.md': 'tool/hf/README.md',
  'LICENSE-FUTO.txt': 'example/assets/models/futoSwipe/LICENSE-FUTO.txt',
};

Future<void> main(List<String> arguments) async {
  if (arguments.any((argument) => argument != '--dry-run')) {
    stderr.writeln('Usage: dart run tool/publish_models.dart [--dry-run]');
    exitCode = 64;
    return;
  }
  final dryRun = arguments.contains('--dry-run');
  final root = File.fromUri(Platform.script).parent.parent;
  final manifest = await readManifest(root);
  final models = hfModels(manifest);
  checkRuntimeNames(models);

  final pinned = [
    for (final model in models)
      if (model.commit != null) model,
  ];
  final problems = await hfProblems(pinned);
  if (problems.isNotEmpty) {
    throw StateError(
      '${problems.join('\n')}\n'
      'A pinned file never changes. To publish other bytes, remove the commit '
      'of the entry.',
    );
  }
  stdout.writeln('OK: ${pinned.length} models match Hugging Face');

  final upload = [
    for (final model in models)
      if (model.commit == null) model,
  ];
  for (final model in upload) {
    await _checkLocal(root, model);
  }
  final changedFiles = await _changedRepositoryFiles(root);
  if (upload.isEmpty && changedFiles.isEmpty) {
    stdout.writeln('Nothing to upload');
  } else {
    stdout.writeln(
      'To upload: ${[...upload.map((m) => m.name), ...changedFiles].join(', ')}',
    );
    if (dryRun) return;
    final commit = await _upload(root, upload, changedFiles);
    for (final model in upload) {
      model.commit = commit;
    }
    final uploadProblems = await hfProblems(upload);
    if (uploadProblems.isNotEmpty) throw StateError(uploadProblems.join('\n'));
    setCommits(manifest, upload);
    await writeManifest(root, manifest);
    stdout.writeln('Uploaded Hugging Face commit $commit');
  }
  if (dryRun) return;

  final set = catalog(models);
  final previous = await PrebuiltManifest.load(root.uri);
  await PrebuiltManifest(
    sourceKey: previous?.sourceKey ?? (await computeSourceKey(root.uri)).key,
    release: previous?.release,
    targets: previous?.targets ?? const {},
    runtimeFiles: set,
  ).save(root.uri);
  await File('${root.path}/$catalogDartPath').writeAsString(catalogDart(set));
  stdout.writeln(
    'Wrote runtimeFiles and $catalogDartPath for ${set.files.length} models',
  );
}

Future<void> _checkLocal(Directory root, HfModel model) async {
  final file = model.file(root);
  if (!await file.exists()) {
    throw StateError('${model.path} is not on Hugging Face and not here');
  }
  final digest = '${await sha256.bind(file.openRead()).first}';
  if (await file.length() != model.bytes || digest != model.sha256) {
    throw StateError(
      '${model.path} does not match its entry in $fonnxManifestPath',
    );
  }
}

/// The names in [_repositoryFiles] whose content on Hugging Face `main`
/// differs from this package.
Future<List<String>> _changedRepositoryFiles(Directory root) async {
  final changed = <String>[];
  final client = HttpClient();
  try {
    for (final MapEntry(key: name, value: path) in _repositoryFiles.entries) {
      final local = await File('${root.path}/$path').readAsString();
      final response = await (await client.getUrl(
        Uri.parse('https://huggingface.co/$hfRepository/resolve/main/$name'),
      )).close();
      final remote = response.statusCode == 200
          ? await response.transform(utf8.decoder).join()
          : null;
      if (response.statusCode != 200) await response.drain<void>();
      if (remote != local) changed.add(name);
    }
  } finally {
    client.close();
  }
  return changed;
}

/// Uploads [models] and [files] in one Hugging Face commit, and returns the
/// commit hash.
Future<String> _upload(
  Directory root,
  List<HfModel> models,
  List<String> files,
) async {
  final staging = await Directory.systemTemp.createTemp('fonnx_hf_upload_');
  try {
    for (final model in models) {
      await model.file(root).copy('${staging.path}/${model.name}');
    }
    for (final name in files) {
      await File(
        '${root.path}/${_repositoryFiles[name]}',
      ).copy('${staging.path}/$name');
    }
    final names = [...models.map((m) => m.name), ...files];
    final result = await Process.run('hf', [
      'upload',
      hfRepository,
      staging.path,
      '.',
      '--repo-type',
      'model',
      '--commit-message',
      'fonnx: ${names.join(', ')}',
    ]);
    stdout.write(result.stdout);
    stderr.write(result.stderr);
    if (result.exitCode != 0) {
      throw ProcessException('hf', const ['upload'], '', result.exitCode);
    }
    final match = RegExp(
      r'/commit/([0-9a-f]{40})',
    ).firstMatch('${result.stdout}${result.stderr}');
    if (match == null) {
      throw StateError('hf upload did not print the commit URL');
    }
    return match.group(1)!;
  } finally {
    await staging.delete(recursive: true);
  }
}
