import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:native_prebuilt/native_prebuilt.dart';
import 'package:native_prebuilt/src/cli.dart';
import 'package:native_prebuilt/src/publisher.dart';
import 'package:native_prebuilt/src/release_tool.dart';
import 'package:path/path.dart' as p;

import '../hook/upstream_ort.dart';

/// The shared release command publishes the hook outputs. FONNX retains ORT's
/// upstream URLs. It also rehosts the existing dynamic iOS ORT base, unchanged,
/// so every package-owned consumer file belongs to the new immutable release.
Future<void> main(List<String> arguments) => runCommand(
  arguments,
  ArgParser()
    ..addOption('package', defaultsTo: '.')
    ..addOption('repo')
    ..addOption('staging')
    ..addFlag('dry-run'),
  'dart run tool/release_native.dart [--dry-run] [--repo owner/name] <build dirs...>',
  (args) async {
    if (args.rest.isEmpty) {
      throw StateError('Pass the build output directories');
    }
    await releaseNative(
      packageRoot: packageRootOf(args),
      directories: args.rest.map(Directory.new).toList(),
      repository: repositoryOf(args),
      staging: await stagingOf(args, 'fonnx_native_release_'),
      publisher: args.flag('dry-run') ? null : GhPublisher(log: log),
    );
    return 0;
  },
);

Future<PrebuiltManifest> releaseNative({
  required Uri packageRoot,
  required List<Directory> directories,
  required String repository,
  required Directory staging,
  Publisher? publisher,
}) async {
  final upstream = await loadUpstreamOrt(packageRoot);
  final skippedAssets = <String>{};
  // Verify the preserved inputs before the shared publisher uploads anything.
  for (final directory in directories) {
    await for (final entity in directory.list(recursive: true)) {
      if (entity is! File || p.basename(entity.path) != targetDescriptionName) {
        continue;
      }
      final description = jsonDecode(await entity.readAsString()) as Map;
      final target = description['target'] as String;
      final ort = upstream[target];
      if (ort == null) throw StateError('Unsupported ORT target $target');
      final files = (description['files'] as List).cast<Map>();
      final record = files.singleWhere((f) => f['asset'] == ortAsset);
      if (record['name'] != ort.name || record['sha256'] != ort.sha256) {
        throw StateError('$target did not use the pinned upstream ORT file');
      }
      if (!target.startsWith('ios-')) {
        skippedAssets.add(nativeAssetName(target, ort.name));
      }
    }
  }
  final manifest = await releaseTargets(
    packageRoot: packageRoot,
    targetDirectories: directories,
    repository: repository,
    staging: staging,
    publisher: publisher == null
        ? null
        : _OwnedFilesPublisher(publisher, skippedAssets),
    log: log,
  );
  final converted = PrebuiltManifest(
    sourceKey: manifest.sourceKey,
    release: manifest.release,
    runtimeFiles: manifest.runtimeFiles,
    targets: {
      for (final entry in manifest.targets.entries)
        entry.key: PrebuiltTarget(
          runner: entry.value.runner,
          toolchain: entry.value.toolchain,
          minOSVersion: entry.value.minOSVersion,
          files: [
            for (final file in entry.value.files)
              file.asset == ortAsset && !entry.key.startsWith('ios-')
                  ? upstream[entry.key]!
                  : file,
          ],
        ),
    },
  );
  await converted.save(packageRoot);
  return converted;
}

final class _OwnedFilesPublisher implements Publisher {
  _OwnedFilesPublisher(this.publisher, this.skipped);
  final Publisher publisher;
  final Set<String> skipped;

  @override
  Future<void> publish({
    required String repository,
    required String tag,
    required List<File> assets,
    required String notes,
  }) => publisher.publish(
    repository: repository,
    tag: tag,
    assets: assets.where((f) => !skipped.contains(p.basename(f.path))).toList(),
    notes: '$notes ORT uses the pinned upstream URLs in prebuilt.json.',
  );

  @override
  Future<Map<String, String>?> publishedAssetDigests({
    required String repository,
    required String tag,
  }) => publisher.publishedAssetDigests(repository: repository, tag: tag);
}
