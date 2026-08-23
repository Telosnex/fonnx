import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln(
      'Usage: dart run tool/materialize_runtime_artifacts.dart '
      '<target> <output-directory>',
    );
    exitCode = 64;
    return;
  }
  final root = File.fromUri(Platform.script).parent.parent;
  final manifest =
      jsonDecode(
            await File(
              '${root.path}/native_artifacts/manifest.json',
            ).readAsString(),
          )
          as Map<String, dynamic>;
  final targets = manifest['nativeArtifacts'] as Map<String, dynamic>;
  final target = targets[arguments[0]] as Map<String, dynamic>?;
  if (target == null) throw ArgumentError.value(arguments[0], 'target');
  final output = Directory(arguments[1])..createSync(recursive: true);
  final cache = Directory('${root.path}/build/runtime-artifact-downloads')
    ..createSync(recursive: true);

  for (final component in const ['onnxRuntime', 'extensions']) {
    final record = target[component] as Map<String, dynamic>;
    final expectedHash = record['sha256'] as String;
    final archiveFile = File('${cache.path}/$expectedHash.archive');
    if (!await archiveFile.exists() ||
        await _hash(archiveFile) != expectedHash) {
      await _download(
        Uri.parse(record['url'] as String),
        archiveFile,
        expectedHash,
      );
    }
    final suffix = record['libraryEntrySuffix'] as String;
    final archiveBytes = await archiveFile.readAsBytes();
    final archive = Uri.parse(record['url'] as String).path.endsWith('.tgz')
        ? TarDecoder().decodeBytes(GZipDecoder().decodeBytes(archiveBytes))
        : ZipDecoder().decodeBytes(archiveBytes, verify: true);
    final matches = archive.files
        .where(
          (entry) =>
              entry.isFile && entry.name.replaceAll('\\', '/').endsWith(suffix),
        )
        .toList();
    if (matches.length != 1) {
      throw StateError('Expected one $suffix, found ${matches.length}');
    }
    final name = switch ((arguments[0], component)) {
      (final value, 'onnxRuntime') when value.startsWith('windows-') =>
        'onnxruntime.dll',
      (final value, 'extensions') when value.startsWith('windows-') =>
        'ortextensions.dll',
      (final value, 'onnxRuntime')
          when value.startsWith('ios-') || value.startsWith('macos-') =>
        'libonnxruntime.dylib',
      (final value, 'extensions')
          when value.startsWith('ios-') || value.startsWith('macos-') =>
        'libortextensions.dylib',
      (_, 'onnxRuntime') => 'libonnxruntime.so',
      (_, 'extensions') => 'libortextensions.so',
      _ => throw StateError(component),
    };
    final bytes = matches.single.readBytes();
    if (bytes == null || bytes.isEmpty) throw StateError('Empty $suffix');
    final file = File('${output.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    final alias = switch ((arguments[0], component)) {
      (final value, 'onnxRuntime')
          when value.startsWith('macos-') || value.startsWith('ios-') =>
        'libonnxruntime.1.dylib',
      (final value, 'extensions')
          when value.startsWith('macos-') || value.startsWith('ios-') =>
        'libortextensions.0.dylib',
      (final value, 'onnxRuntime') when value.startsWith('linux-') =>
        'libonnxruntime.so.1',
      (final value, 'extensions') when value.startsWith('linux-') =>
        'libortextensions.so.0',
      _ => null,
    };
    if (alias != null) {
      final link = Link('${output.path}/$alias');
      if (await link.exists()) await link.delete();
      await link.create(name);
    }
    if (arguments[0].startsWith('ios-') && component == 'onnxRuntime') {
      final framework = Directory('${output.path}/onnxruntime.framework');
      await framework.create();
      final link = Link('${framework.path}/onnxruntime');
      if (await link.exists()) await link.delete();
      await link.create('../libonnxruntime.dylib');
    }
    stdout.writeln('$component: ${file.path} (${bytes.length} bytes)');
  }
}

Future<void> _download(Uri uri, File destination, String expectedHash) async {
  stderr.writeln('downloading $uri');
  final partial = File('${destination.path}.partial');
  if (await partial.exists()) await partial.delete();
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.userAgentHeader, 'fonnx-runtime-test/1');
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('HTTP ${response.statusCode}', uri: uri);
    }
    await response.pipe(partial.openWrite());
  } finally {
    client.close(force: true);
  }
  final actual = await _hash(partial);
  if (actual != expectedHash) {
    await partial.delete();
    throw StateError(
      'Hash mismatch for $uri: expected $expectedHash, got $actual',
    );
  }
  await partial.rename(destination.path);
}

Future<String> _hash(File file) =>
    sha256.bind(file.openRead()).first.then((digest) => digest.toString());
