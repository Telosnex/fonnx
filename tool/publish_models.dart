import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:fonnx/runtime_models.dart';
import 'package:native_prebuilt/src/publisher.dart';
import 'package:native_prebuilt/src/release_tool.dart';
import 'package:path/path.dart' as p;

const _modelRoot = 'example/assets/models';
const _manifestPath = 'native_artifacts/manifest.json';
const _futoManifestPath = 'example/assets/models/futoSwipe/manifest.json';
const _lfsHeader = 'version https://git-lfs.github.com/spec/v1';

Future<void> main(List<String> arguments) async {
  try {
    final options = _Options.parse(arguments);
    if (options.help) {
      stdout.write(_usage);
      return;
    }
    await publishModels(
      packageRoot: options.packageRoot,
      repository: options.repository,
      dryRun: options.dryRun,
      staging: options.staging,
      log: stdout.writeln,
    );
  } on FormatException catch (error) {
    stderr.writeln('publish_models: ${error.message}');
    stderr.writeln(_usage);
    exitCode = 64;
  } on Object catch (error, stackTrace) {
    stderr.writeln('publish_models: $error');
    stderr.writeln(stackTrace);
    exitCode = 1;
  }
}

/// Checks and publishes every example ONNX model as one runtime-file set.
///
/// This calls native_prebuilt's [runtimeRelease], which writes
/// `native_artifacts/prebuilt.json` and `lib/src/native_prebuilt.g.dart`.
/// Passing [dryRun] writes those files and the compressed staging assets but
/// does not create or update a GitHub release.
Future<void> publishModels({
  required Directory packageRoot,
  required String repository,
  required bool dryRun,
  Directory? staging,
  void Function(String message)? log,
}) async {
  _validateRepository(repository);
  final root = packageRoot.absolute;
  final models = await _checkModels(root);
  final releaseStaging =
      staging?.absolute ??
      await Directory.systemTemp.createTemp('fonnx_runtime_release_');
  final aliases = await Directory.systemTemp.createTemp(
    'fonnx_runtime_models_',
  );

  try {
    final releaseFiles = <File>[];
    for (final model in models) {
      final releaseName = runtimeModelNamesByPath[model.path]!;
      if (p.basename(model.file.path) == releaseName) {
        releaseFiles.add(model.file);
      } else {
        // runtimeRelease uses basenames as public names. Copy only files that
        // need an alias. This resolves nested basename collisions without
        // copying the large models whose basenames are already unique.
        releaseFiles.add(
          await model.file.copy(p.join(aliases.path, releaseName)),
        );
      }
    }

    log?.call(
      '${dryRun ? 'Preparing' : 'Publishing'} ${releaseFiles.length} '
      'verified models for $repository',
    );
    log?.call('Runtime release staging: ${releaseStaging.path}');
    await runtimeRelease(
      packageRoot: root.uri,
      files: releaseFiles,
      repository: repository,
      staging: releaseStaging,
      publisher: dryRun ? null : GhPublisher(log: log),
      log: log,
    );
  } finally {
    await aliases.delete(recursive: true);
  }
}

Future<List<_CheckedModel>> _checkModels(Directory packageRoot) async {
  final manifestFile = File(p.join(packageRoot.path, _manifestPath));
  final manifest = await _readObject(manifestFile);
  final modelEntries = _objectField(manifest, 'models', manifestFile.path);

  final expectedManifestPaths = <String>{
    for (final path in runtimeModelNamesByPath.keys) '$_modelRoot/$path',
  };
  final exampleManifestPaths = modelEntries.keys
      .where(
        (path) => path.startsWith('$_modelRoot/') && path.endsWith('.onnx'),
      )
      .toSet();
  _requireSameSet(
    expectedManifestPaths,
    exampleManifestPaths,
    'the public runtime-model map',
    '$_manifestPath models',
  );

  final diskPaths = <String>{};
  final modelDirectory = Directory(p.join(packageRoot.path, _modelRoot));
  if (!await modelDirectory.exists()) {
    throw StateError('${modelDirectory.path} does not exist.');
  }
  await for (final entity in modelDirectory.list(recursive: true)) {
    if (entity is File && entity.path.toLowerCase().endsWith('.onnx')) {
      diskPaths.add(
        p
            .relative(entity.path, from: packageRoot.path)
            .replaceAll(p.separator, '/'),
      );
    }
  }
  _requireSameSet(
    expectedManifestPaths,
    diskPaths,
    'the public runtime-model map',
    'ONNX files on disk',
  );

  final checked = <_CheckedModel>[];
  final entriesByModelPath = <String, Map<String, Object?>>{};
  for (final modelPath in runtimeModelNamesByPath.keys) {
    final manifestPath = '$_modelRoot/$modelPath';
    final rawEntry = modelEntries[manifestPath];
    if (rawEntry is! Map) {
      throw FormatException('$_manifestPath models.$manifestPath is invalid.');
    }
    final entry = rawEntry.cast<String, Object?>();
    entriesByModelPath[modelPath] = entry;
    if (entry['path'] != manifestPath) {
      throw StateError(
        '$_manifestPath models.$manifestPath has path ${entry['path']}.',
      );
    }
    final expectedHash = entry['sha256'];
    final expectedBytes = entry['bytes'];
    if (expectedHash is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(expectedHash)) {
      throw FormatException(
        '$_manifestPath models.$manifestPath has an invalid sha256.',
      );
    }
    if (expectedBytes is! int || expectedBytes < 0) {
      throw FormatException(
        '$_manifestPath models.$manifestPath has invalid bytes.',
      );
    }

    final file = File(
      p.joinAll([packageRoot.path, _modelRoot, ...modelPath.split('/')]),
    );
    if (!await file.exists()) {
      throw StateError('${file.path} does not exist.');
    }
    if (await _isLfsPointer(file)) {
      throw StateError(
        '${file.path} is a Git LFS pointer. Hydrate the model before '
        'publishing.',
      );
    }
    final actualBytes = await file.length();
    if (actualBytes != expectedBytes) {
      throw StateError(
        '${file.path} has $actualBytes bytes; the manifest pins '
        '$expectedBytes.',
      );
    }
    final actualHash = (await sha256.bind(file.openRead()).first).toString();
    if (actualHash != expectedHash) {
      throw StateError(
        '${file.path} has SHA-256 $actualHash; the manifest pins '
        '$expectedHash.',
      );
    }
    checked.add(_CheckedModel(modelPath, file));
  }

  await _checkFutoMetadata(packageRoot, entriesByModelPath);
  final releaseNames = runtimeModelNamesByPath.values.toList();
  if (releaseNames.toSet().length != releaseNames.length) {
    throw StateError('Runtime model release names are not unique.');
  }
  return checked;
}

Future<void> _checkFutoMetadata(
  Directory packageRoot,
  Map<String, Map<String, Object?>> modelEntries,
) async {
  final file = File(p.join(packageRoot.path, _futoManifestPath));
  final manifest = await _readObject(file);
  final outputs = _objectField(manifest, 'outputs', file.path);
  final futoPaths = runtimeModelNamesByPath.keys
      .where((path) => path.startsWith('futoSwipe/'))
      .map((path) => path.substring('futoSwipe/'.length))
      .toSet();
  _requireSameSet(
    futoPaths,
    outputs.keys.toSet(),
    'the FUTO runtime-model map',
    '$_futoManifestPath outputs',
  );
  for (final path in futoPaths) {
    final output = outputs[path];
    if (output is! Map) {
      throw FormatException('$_futoManifestPath outputs.$path is invalid.');
    }
    final model = modelEntries['futoSwipe/$path']!;
    if (output['sha256'] != model['sha256'] ||
        output['bytes'] != model['bytes']) {
      throw StateError(
        'FUTO metadata for $path disagrees with $_manifestPath.',
      );
    }
  }

  const expectedMetadata = <String, (String, String)>{
    'honorable_sturgeon': ('encoder', 'honorable_sturgeon'),
    'magic_macaw': ('decoder', 'magic_macaw'),
    'hungry_jellyfish': ('contextlm', 'hungry_jellyfish'),
  };
  for (final entry in expectedMetadata.entries) {
    final metadataFile = File(
      p.join(
        packageRoot.path,
        _modelRoot,
        'futoSwipe',
        entry.key,
        'metadata.json',
      ),
    );
    final metadata = await _readObject(metadataFile);
    if (metadata['kind'] != entry.value.$1 ||
        metadata['codename'] != entry.value.$2) {
      throw StateError(
        '${metadataFile.path} does not describe the expected FUTO model.',
      );
    }
  }
}

Future<Map<String, Object?>> _readObject(File file) async {
  if (!await file.exists()) throw StateError('${file.path} does not exist.');
  final decoded = jsonDecode(await file.readAsString());
  if (decoded is! Map) throw FormatException('${file.path} is not an object.');
  return decoded.cast<String, Object?>();
}

Map<String, Object?> _objectField(
  Map<String, Object?> object,
  String field,
  String source,
) {
  final value = object[field];
  if (value is! Map) throw FormatException('$source $field is not an object.');
  return value.cast<String, Object?>();
}

Future<bool> _isLfsPointer(File file) async {
  final bytes = await file
      .openRead(0, _lfsHeader.length)
      .fold<List<int>>(<int>[], (all, part) => all..addAll(part));
  return ascii.decode(bytes, allowInvalid: true) == _lfsHeader;
}

void _requireSameSet(
  Set<String> expected,
  Set<String> actual,
  String expectedName,
  String actualName,
) {
  final missing = expected.difference(actual).toList()..sort();
  final extra = actual.difference(expected).toList()..sort();
  if (missing.isEmpty && extra.isEmpty) return;
  throw StateError(
    '$expectedName and $actualName disagree.'
    '${missing.isEmpty ? '' : '\nMissing from $actualName: ${missing.join(', ')}'}'
    '${extra.isEmpty ? '' : '\nOnly in $actualName: ${extra.join(', ')}'}',
  );
}

void _validateRepository(String repository) {
  if (!RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$').hasMatch(repository)) {
    throw FormatException('--repo must be an owner/name GitHub repository.');
  }
}

final class _CheckedModel {
  const _CheckedModel(this.path, this.file);

  final String path;
  final File file;
}

final class _Options {
  const _Options({
    required this.packageRoot,
    required this.repository,
    required this.dryRun,
    required this.staging,
    required this.help,
  });

  factory _Options.parse(List<String> arguments) {
    var package = '.';
    String? repository;
    String? staging;
    var dryRun = false;
    var help = false;
    for (var i = 0; i < arguments.length; i++) {
      final argument = arguments[i];
      String value(String name) {
        if (i + 1 == arguments.length) {
          throw FormatException('$name needs a value.');
        }
        return arguments[++i];
      }

      if (argument == '--dry-run') {
        dryRun = true;
      } else if (argument == '--help' || argument == '-h') {
        help = true;
      } else if (argument == '--repo') {
        repository = value('--repo');
      } else if (argument.startsWith('--repo=')) {
        repository = argument.substring('--repo='.length);
      } else if (argument == '--package') {
        package = value('--package');
      } else if (argument.startsWith('--package=')) {
        package = argument.substring('--package='.length);
      } else if (argument == '--staging') {
        staging = value('--staging');
      } else if (argument.startsWith('--staging=')) {
        staging = argument.substring('--staging='.length);
      } else {
        throw FormatException('Unknown argument: $argument');
      }
    }
    final resolvedRepository =
        repository ?? Platform.environment['GITHUB_REPOSITORY'];
    if (!help && (resolvedRepository == null || resolvedRepository.isEmpty)) {
      throw FormatException('Pass --repo owner/name or set GITHUB_REPOSITORY.');
    }
    return _Options(
      packageRoot: Directory(package),
      repository: resolvedRepository ?? 'owner/repository',
      dryRun: dryRun,
      staging: staging == null ? null : Directory(staging),
      help: help,
    );
  }

  final Directory packageRoot;
  final String repository;
  final bool dryRun;
  final Directory? staging;
  final bool help;
}

const _usage = '''
Usage: dart run tool/publish_models.dart [options]

Checks every example ONNX model against native_artifacts/manifest.json, then
publishes the complete native_prebuilt runtime-file set.

Options:
  --repo owner/name  GitHub repository (default: GITHUB_REPOSITORY)
  --dry-run          Write staged assets and generated files; do not upload
  --package path     Package root (default: current directory)
  --staging path     Directory for compressed release assets
  -h, --help         Show this help
''';
