// Native-assets build hook for fonnx.
//
// ONNX Runtime is expensive to compile but Microsoft publishes dynamic
// libraries for Linux, macOS, Windows, and Android. FONNX release CI fills
// the dynamic-iOS and selected-op Extensions publishing gaps. This hook
// downloads the exact artifact selected by target OS/architecture, verifies
// its SHA-256, extracts only the libraries, and emits bundled code assets.
//
// Downloads and extracted files live in a content-addressed cache outside
// hooks_runner's environment-sensitive cache. A cold build downloads once;
// subsequent builds only copy the verified artifact into the hook output.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';
import 'package:path/path.dart' as p;

const _ortAssetName = 'onnx/ort_ffi_bindings.dart';
const _ortExtensionsAssetName = 'onnx/ort_extensions.dart';
const _ortSessionFinalizerAssetName = 'onnx/ort_session_finalizer.dart';

final class _Artifact {
  const _Artifact({
    required this.url,
    required this.sha256,
    required this.libraryEntrySuffix,
  });

  factory _Artifact.fromJson(Object? value, String label) {
    if (value is! Map<String, Object?>) {
      throw FormatException('$label must be an object');
    }
    final url = value['url'];
    final digest = value['sha256'];
    final suffix = value['libraryEntrySuffix'];
    if (url is! String ||
        !url.startsWith('https://') ||
        digest is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(digest) ||
        suffix is! String ||
        suffix.isEmpty ||
        suffix.contains('..')) {
      throw FormatException('Invalid artifact record: $label');
    }
    return _Artifact(url: url, sha256: digest, libraryEntrySuffix: suffix);
  }

  final String url;
  final String sha256;
  final String libraryEntrySuffix;

  bool get isZip {
    final path = Uri.parse(url).path;
    return path.endsWith('.zip') || path.endsWith('.aar');
  }
}

final class _ArtifactManifest {
  const _ArtifactManifest({
    required this.ort,
    required this.extensions,
    required this.file,
  });

  final Map<String, _Artifact> ort;
  final Map<String, _Artifact> extensions;
  final File file;
}

Future<_ArtifactManifest> _loadArtifactManifest(Uri packageRoot) async {
  final file = File.fromUri(
    packageRoot.resolve('native_artifacts/manifest.json'),
  );
  final decoded = jsonDecode(await file.readAsString());
  if (decoded is! Map<String, Object?> ||
      decoded['schema'] != 1 ||
      decoded['profile'] != 1 ||
      decoded['finalizerAbi'] != 1 ||
      decoded['webWorkerProtocolAbi'] != 1) {
    throw const FormatException('Unsupported fonnx artifact manifest/profile');
  }
  final records = decoded['nativeArtifacts'];
  if (records is! Map<String, Object?> || records.length != 10) {
    throw const FormatException('Expected exactly 10 native target records');
  }
  final ort = <String, _Artifact>{};
  final extensions = <String, _Artifact>{};
  for (final entry in records.entries) {
    final target = entry.value;
    if (target is! Map<String, Object?> || target.length != 2) {
      throw FormatException('Invalid native target record: ${entry.key}');
    }
    ort[entry.key] = _Artifact.fromJson(
      target['onnxRuntime'],
      '${entry.key}.onnxRuntime',
    );
    extensions[entry.key] = _Artifact.fromJson(
      target['extensions'],
      '${entry.key}.extensions',
    );
  }
  return _ArtifactManifest(ort: ort, extensions: extensions, file: file);
}

void main(List<String> args) async {
  final hookLog = _HookLogBuffer('fonnx');
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final hookStopwatch = Stopwatch()..start();
    final artifactStopwatch = Stopwatch()..start();
    final manifest = await _loadArtifactManifest(input.packageRoot);
    final os = input.config.code.targetOS;

    if (os == OS.fuchsia) {
      throw UnsupportedError('fonnx does not support ONNX Runtime on Fuchsia.');
    }

    final architecture = input.config.code.targetArchitecture;
    final sdkSuffix = os == OS.iOS
        ? switch (input.config.code.iOS.targetSdk) {
            IOSSdk.iPhoneOS => '-iphoneos',
            IOSSdk.iPhoneSimulator => '-iphonesimulator',
            final sdk => throw UnsupportedError('Unsupported iOS SDK: $sdk.'),
          }
        : '';
    final key = '${os.name}-${architecture.name}$sdkSuffix';
    final artifact = manifest.ort[key];
    if (artifact == null) {
      throw UnsupportedError(
        'No fonnx ONNX Runtime artifact for $key. Supported targets: '
        '${manifest.ort.keys.join(', ')}. Intel Apple targets are '
        'intentionally not supported.',
      );
    }

    await _publishArtifact(
      input: input,
      output: output,
      artifact: artifact,
      outputFileName: os.dylibFileName('onnxruntime'),
      assetName: _ortAssetName,
      log: hookLog,
    );

    final extensionsArtifact = manifest.extensions[key];
    if (extensionsArtifact != null) {
      await _publishArtifact(
        input: input,
        output: output,
        artifact: extensionsArtifact,
        outputFileName: os.dylibFileName('ortextensions'),
        assetName: _ortExtensionsAssetName,
        log: hookLog,
      );
    }
    final artifactDuration = artifactStopwatch.elapsed;

    final finalizerStopwatch = Stopwatch()..start();
    await CBuilder.library(
      name: 'fonnx_ort_session_finalizer',
      assetName: _ortSessionFinalizerAssetName,
      sources: [
        input.packageRoot.resolve('src/ort_session_finalizer.c').toFilePath(),
      ],
      includes: [input.packageRoot.resolve('src').toFilePath()],
      libraries: [if (os == OS.windows) 'ole32'],
    ).run(input: input, output: output);
    final finalizerDuration = finalizerStopwatch.elapsed;

    // Make changes to the hook invalidate hooks_runner's own dependency graph.
    output.dependencies.add(input.packageRoot.resolve('hook/build.dart'));
    output.dependencies.add(manifest.file.uri);
    output.dependencies.add(
      input.packageRoot.resolve('src/ort_session_finalizer.c'),
    );
    output.dependencies.add(
      input.packageRoot.resolve('src/ort_session_finalizer.h'),
    );

    hookLog.add(
      'Hook completed in ${_formatDuration(hookStopwatch.elapsed)} '
      '(artifacts ${_formatDuration(artifactDuration)}, '
      'finalizer ${_formatDuration(finalizerDuration)})',
    );
  }).whenComplete(hookLog.flush);
}

Future<void> _publishArtifact({
  required BuildInput input,
  required BuildOutputBuilder output,
  required _Artifact artifact,
  required String outputFileName,
  required String assetName,
  required _HookLogBuffer log,
}) async {
  final publishStopwatch = Stopwatch()..start();
  final cachedLibrary = await _ensureCachedLibrary(
    artifact: artifact,
    outputFileName: outputFileName,
    log: log,
  );
  final outputDirectory = Directory.fromUri(input.outputDirectory);
  await outputDirectory.create(recursive: true);
  final publishedLibrary = File(p.join(outputDirectory.path, outputFileName));
  await cachedLibrary.copy(publishedLibrary.path);
  output.assets.code.add(
    CodeAsset(
      package: input.packageName,
      name: assetName,
      linkMode: DynamicLoadingBundled(),
      file: publishedLibrary.uri,
    ),
  );
  log.add(
    'Published $outputFileName in '
    '${_formatDuration(publishStopwatch.elapsed)}',
  );
}

Future<File> _ensureCachedLibrary({
  required _Artifact artifact,
  required String outputFileName,
  required _HookLogBuffer log,
}) async {
  // One archive (notably an Android AAR) can contain several ABI-specific
  // libraries with the same output filename. Include the selected entry in
  // the cache key so an arm64 extraction can never satisfy an x64 build.
  final entryKey = sha256
      .convert(artifact.libraryEntrySuffix.codeUnits)
      .toString()
      .substring(0, 16);
  final artifactDirectory = Directory(
    p.join(_cacheRoot().path, 'artifacts', artifact.sha256),
  );
  final extractionDirectory = Directory(
    p.join(artifactDirectory.path, entryKey),
  );
  final library = File(p.join(extractionDirectory.path, outputFileName));
  if (await library.exists()) return library;

  await extractionDirectory.create(recursive: true);
  final extractionLock = File(
    p.join(extractionDirectory.path, '.extract.lock'),
  );
  return _withExclusiveLock(extractionLock, () async {
    if (await library.exists()) return library;

    // The downloaded archive is shared by all ABI-specific extraction dirs.
    // Give it a separate lock so concurrent Android ABI builds download the
    // large AAR once without racing on artifact.partial.
    final archiveFile = File(
      p.join(
        artifactDirectory.path,
        artifact.isZip ? 'artifact.zip' : 'artifact.tgz',
      ),
    );
    await _withExclusiveLock(
      File(p.join(artifactDirectory.path, '.download.lock')),
      () => _ensureVerifiedDownload(artifact, archiveFile, log),
    );
    await _extractLibrary(artifact, archiveFile, library, log);
    return library;
  });
}

Future<void> _ensureVerifiedDownload(
  _Artifact artifact,
  File archiveFile,
  _HookLogBuffer log,
) async {
  if (await archiveFile.exists()) {
    final digest = await _sha256Of(archiveFile);
    if (digest == artifact.sha256) return;
    await archiveFile.delete();
  }

  final partial = File('${archiveFile.path}.partial');
  if (await partial.exists()) await partial.delete();

  final downloadStopwatch = Stopwatch()..start();
  log.add('Downloading ${artifact.url}');
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(artifact.url));
    request.headers.set(HttpHeaders.userAgentHeader, 'fonnx-native-assets/1');
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Download failed with HTTP ${response.statusCode}',
        uri: Uri.parse(artifact.url),
      );
    }
    await response.pipe(partial.openWrite());
  } finally {
    client.close(force: true);
  }

  final actualDigest = await _sha256Of(partial);
  if (actualDigest != artifact.sha256) {
    await partial.delete();
    throw StateError(
      'SHA-256 mismatch for ${artifact.url}: expected ${artifact.sha256}, '
      'got $actualDigest. The file was deleted.',
    );
  }
  await partial.rename(archiveFile.path);
  log.add(
    'Download completed in ${_formatDuration(downloadStopwatch.elapsed)}',
  );
}

Future<void> _extractLibrary(
  _Artifact artifact,
  File archiveFile,
  File outputFile,
  _HookLogBuffer log,
) async {
  final extractionStopwatch = Stopwatch()..start();
  log.add('Extracting ${p.basename(outputFile.path)}');
  final encoded = await archiveFile.readAsBytes();
  final archive = artifact.isZip
      ? ZipDecoder().decodeBytes(encoded, verify: true)
      : TarDecoder().decodeBytes(GZipDecoder().decodeBytes(encoded));

  final matches = archive.files
      .where(
        (entry) =>
            entry.isFile &&
            entry.name
                .replaceAll('\\', '/')
                .endsWith(artifact.libraryEntrySuffix),
      )
      .toList();
  if (matches.length != 1) {
    throw StateError(
      'Expected exactly one ${artifact.libraryEntrySuffix} in ${artifact.url}, '
      'found ${matches.map((entry) => entry.name).toList()}.',
    );
  }

  final bytes = matches.single.readBytes();
  if (bytes == null || bytes.isEmpty) {
    throw StateError('Extracted ONNX Runtime library is empty.');
  }
  final partial = File('${outputFile.path}.partial');
  await partial.writeAsBytes(bytes, flush: true);
  await partial.rename(outputFile.path);
  log.add(
    'Extraction completed in ${_formatDuration(extractionStopwatch.elapsed)}',
  );
}

/// Collects hook messages so hooks_runner does not insert a blank line after
/// every separately streamed stderr chunk.
final class _HookLogBuffer {
  _HookLogBuffer(this.tag);

  final String tag;
  final List<String> _lines = [];

  void add(String message) {
    final normalized = message.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    for (final line in normalized.split('\n')) {
      if (line.trim().isEmpty) continue;
      _lines.add('[$tag] $line');
    }
  }

  void flush() {
    if (_lines.isEmpty) return;
    // hooks_runner adds the terminating newline while capturing this chunk.
    stderr.write(_lines.join('\n'));
  }
}

String _formatDuration(Duration duration) {
  final millis = duration.inMilliseconds;
  if (millis < 1000) return '${millis}ms';
  final seconds = duration.inSeconds;
  final remainderMillis = millis - seconds * 1000;
  if (seconds < 60) {
    return '$seconds.${(remainderMillis ~/ 100).toString()}s';
  }
  final minutes = seconds ~/ 60;
  final remainderSeconds = seconds % 60;
  return '${minutes}m ${remainderSeconds}s';
}

Future<String> _sha256Of(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

Directory _cacheRoot() {
  final xdg = Platform.environment['XDG_CACHE_HOME'];
  if (xdg != null && xdg.isNotEmpty) {
    return Directory(p.join(xdg, 'fonnx'));
  }
  if (Platform.isWindows) {
    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (localAppData != null && localAppData.isNotEmpty) {
      return Directory(p.join(localAppData, 'fonnx', 'Cache'));
    }
  }
  final home =
      Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      (throw StateError(
        'Cannot find a cache root: HOME, USERPROFILE, and XDG_CACHE_HOME '
        'are all unset.',
      ));
  return Directory(p.join(home, '.cache', 'fonnx'));
}

Future<T> _withExclusiveLock<T>(
  File lockFile,
  Future<T> Function() action,
) async {
  await lockFile.parent.create(recursive: true);
  final handle = await lockFile.open(mode: FileMode.append);
  try {
    await handle.lock(FileLock.blockingExclusive);
    try {
      return await action();
    } finally {
      await handle.unlock();
    }
  } finally {
    await handle.close();
  }
}
