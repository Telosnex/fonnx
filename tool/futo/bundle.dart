import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'sources.dart';

// Shared by the artifact gate, focused tests, and the optional replay.
Future<void> verifyFutoSwipeBundle(Directory bundle) async {
  final manifest =
      jsonDecode(await File('${bundle.path}/manifest.json').readAsString())
          as Map;
  if (manifest['modelRevision'] != revision ||
      manifest['executorchSchemaRevision'] != etRevision ||
      manifest['converterVersion'] != 2 ||
      manifest['opset'] != 17 ||
      manifest['irVersion'] != 8) {
    throw StateError('Unexpected FUTO Swipe source or conversion version');
  }
  void keys(Map records, Set<String> expected, String label) {
    if (records.length != expected.length ||
        !expected.containsAll(records.keys)) {
      throw StateError('Unexpected FUTO Swipe $label inventory');
    }
  }

  Future<void> verify(String path, Map record, {String? pinnedHash}) async {
    final hash = record['sha256'];
    final size = record['bytes'];
    if (hash is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash) ||
        size is! int ||
        size <= 0 ||
        (pinnedHash != null && hash != pinnedHash)) {
      throw StateError('Invalid FUTO Swipe record: $path');
    }
    final f = File('${bundle.path}/$path');
    if (await f.length() != size ||
        (await sha256.bind(f.openRead()).first).toString() != hash) {
      throw StateError('FUTO Swipe hash or size mismatch: $path');
    }
  }

  final sources = manifest['sources'] as Map;
  keys(sources, sourceHashes.keys.toSet(), 'source');
  for (final entry in sourceHashes.entries) {
    final record = sources[entry.key] as Map;
    if (record['sha256'] != entry.value ||
        record['url'] != sourceUrl(entry.key)) {
      throw StateError('FUTO Swipe source pin mismatch: ${entry.key}');
    }
  }
  final outputs = manifest['outputs'] as Map;
  keys(outputs, futoSwipeModelPaths, 'model');
  for (final path in futoSwipeModelPaths) {
    await verify(path, outputs[path] as Map);
  }
  final files = manifest['files'] as Map;
  final preserved = sourceHashes.keys.where((name) => !name.endsWith('.pte'));
  keys(files, {
    ...preserved.map(distributedSourcePath),
    'NOTICE.txt',
  }, 'support file');
  for (final source in preserved) {
    final path = distributedSourcePath(source);
    await verify(path, files[path] as Map, pinnedHash: sourceHashes[source]);
    if (files[path]['bytes'] != sources[source]['bytes']) {
      throw StateError('FUTO Swipe source size mismatch: $source');
    }
  }
  await verify(
    'NOTICE.txt',
    files['NOTICE.txt'] as Map,
    pinnedHash: sha256.convert(utf8.encode(futoSwipeNotice)).toString(),
  );
  final expected = {
    ...futoSwipeModelPaths,
    ...files.keys.cast<String>(),
    'manifest.json',
  };
  final absoluteActual = bundle.absolute
      .listSync(recursive: true)
      .whereType<File>()
      .map(
        (f) => p
            .relative(f.path, from: bundle.absolute.path)
            .split(p.separator)
            .join('/'),
      )
      .toSet();
  if (absoluteActual.length != expected.length ||
      !absoluteActual.containsAll(expected)) {
    throw StateError('Unexpected FUTO Swipe bundle files: $absoluteActual');
  }
}
