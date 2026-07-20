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

import 'dart:io';

import 'package:archive/archive.dart';
import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';
import 'package:path/path.dart' as p;

const _ortVersion = '1.27.0';
const _ortAssetName = 'onnx/ort_ffi_bindings.dart';
const _ortExtensionsAssetName = 'onnx/ort_extensions.dart';

final class _Artifact {
  const _Artifact({
    required this.url,
    required this.sha256,
    required this.libraryEntrySuffix,
  });

  final String url;
  final String sha256;
  final String libraryEntrySuffix;

  bool get isZip {
    final path = Uri.parse(url).path;
    return path.endsWith('.zip') || path.endsWith('.aar');
  }
}

const _ortArtifacts = <String, _Artifact>{
  'android-arm': _Artifact(
    url:
        'https://repo.maven.apache.org/maven2/com/microsoft/onnxruntime/'
        'onnxruntime-android/$_ortVersion/'
        'onnxruntime-android-$_ortVersion.aar',
    sha256: '077dec5e2d821234c7dc0aba584bec8f999854b546c754cab93a90741c56fbeb',
    libraryEntrySuffix: 'jni/armeabi-v7a/libonnxruntime.so',
  ),
  'android-arm64': _Artifact(
    url:
        'https://repo.maven.apache.org/maven2/com/microsoft/onnxruntime/'
        'onnxruntime-android/$_ortVersion/'
        'onnxruntime-android-$_ortVersion.aar',
    sha256: '077dec5e2d821234c7dc0aba584bec8f999854b546c754cab93a90741c56fbeb',
    libraryEntrySuffix: 'jni/arm64-v8a/libonnxruntime.so',
  ),
  'android-x64': _Artifact(
    url:
        'https://repo.maven.apache.org/maven2/com/microsoft/onnxruntime/'
        'onnxruntime-android/$_ortVersion/'
        'onnxruntime-android-$_ortVersion.aar',
    sha256: '077dec5e2d821234c7dc0aba584bec8f999854b546c754cab93a90741c56fbeb',
    libraryEntrySuffix: 'jni/x86_64/libonnxruntime.so',
  ),
  'linux-arm64': _Artifact(
    url:
        'https://github.com/microsoft/onnxruntime/releases/download/'
        'v$_ortVersion/onnxruntime-linux-aarch64-$_ortVersion.tgz',
    sha256: '3e4d83ac06924a32a07b6d7f91ce6f852876153fc0bbdf931bf517a140bfbe48',
    libraryEntrySuffix: 'lib/libonnxruntime.so.$_ortVersion',
  ),
  'linux-x64': _Artifact(
    url:
        'https://github.com/microsoft/onnxruntime/releases/download/'
        'v$_ortVersion/onnxruntime-linux-x64-$_ortVersion.tgz',
    sha256: '547e40a48f1fe73e3f812d7c88a948612c23f896b91e4e2ee1e232d7b468246f',
    libraryEntrySuffix: 'lib/libonnxruntime.so.$_ortVersion',
  ),
  'macos-arm64': _Artifact(
    url:
        'https://github.com/microsoft/onnxruntime/releases/download/'
        'v$_ortVersion/onnxruntime-osx-arm64-$_ortVersion.tgz',
    sha256: '545e81c58152353acb0d1e8bd6ce4b62f830c0961f5b3acfedc790ffd76e477a',
    libraryEntrySuffix: 'lib/libonnxruntime.$_ortVersion.dylib',
  ),
  'windows-arm64': _Artifact(
    url:
        'https://github.com/microsoft/onnxruntime/releases/download/'
        'v$_ortVersion/onnxruntime-win-arm64-$_ortVersion.zip',
    sha256: 'a32f2650575b3c20df462e337519fd1cc4105356130d11dba9771c6f374d952f',
    libraryEntrySuffix: 'lib/onnxruntime.dll',
  ),
  'windows-x64': _Artifact(
    url:
        'https://github.com/microsoft/onnxruntime/releases/download/'
        'v$_ortVersion/onnxruntime-win-x64-$_ortVersion.zip',
    sha256: 'c5c81710938e68079ff1a192b04897faabe4b43830d48f39f27ecd4e16138bfc',
    libraryEntrySuffix: 'lib/onnxruntime.dll',
  ),
};

const _ortExtensionsCommitShort = 'fe4e13f4';
const _nativeAssetsReleaseUrl =
    'https://github.com/Telosnex/fonnx/releases/download/'
    'native-assets-ort-1.27.0-ortx-fe4e13f';

const _ortExtensionsArtifacts = <String, _Artifact>{
  'android-arm': _Artifact(
    url:
        '$_nativeAssetsReleaseUrl/'
        'fonnx-ortextensions-$_ortExtensionsCommitShort-android-arm.zip',
    sha256: 'e24e5676fe54902b0e2447fc18b03193cfeaf917446d6a7a33b3242b93bdafa2',
    libraryEntrySuffix: 'libortextensions.so',
  ),
  'android-arm64': _Artifact(
    url:
        '$_nativeAssetsReleaseUrl/'
        'fonnx-ortextensions-$_ortExtensionsCommitShort-android-arm64.zip',
    sha256: 'a71acaaccaa8f243afc0a21e27f5f88d3fbf161499bf1e4bb0160fa56e8f94a6',
    libraryEntrySuffix: 'libortextensions.so',
  ),
  'android-x64': _Artifact(
    url:
        '$_nativeAssetsReleaseUrl/'
        'fonnx-ortextensions-$_ortExtensionsCommitShort-android-x64.zip',
    sha256: 'dbd12c2418094313e1805f61e7ca0bfab9d5bac778d0c1c543d6f79fb4259101',
    libraryEntrySuffix: 'libortextensions.so',
  ),
  'linux-arm64': _Artifact(
    url:
        '$_nativeAssetsReleaseUrl/'
        'fonnx-ortextensions-$_ortExtensionsCommitShort-linux-arm64.zip',
    sha256: '5a8aaa4ad4ad58c8be4d364d081b07eb81f6e8ad0fe40b1aeddd98df205e00c6',
    libraryEntrySuffix: 'libortextensions.so',
  ),
  'linux-x64': _Artifact(
    url:
        '$_nativeAssetsReleaseUrl/'
        'fonnx-ortextensions-$_ortExtensionsCommitShort-linux-x64.zip',
    sha256: '9fed7d4d8a8cd73223428fb31088d714103a3a146038d76461039df65640ac13',
    libraryEntrySuffix: 'libortextensions.so',
  ),
  'macos-arm64': _Artifact(
    url:
        '$_nativeAssetsReleaseUrl/'
        'fonnx-ortextensions-$_ortExtensionsCommitShort-macos-arm64.zip',
    sha256: 'b6560134d7503bc2a00d9350afbf278cccd0706270e90819793eb28df29fba01',
    libraryEntrySuffix: 'libortextensions.dylib',
  ),
  'windows-arm64': _Artifact(
    url:
        '$_nativeAssetsReleaseUrl/'
        'fonnx-ortextensions-$_ortExtensionsCommitShort-windows-arm64.zip',
    sha256: 'b42d856bc2fb3c7904c1b12cc36ec1c5f151ce71f94be6b1e025a9a2f399f0d6',
    libraryEntrySuffix: 'ortextensions.dll',
  ),
  'windows-x64': _Artifact(
    url:
        '$_nativeAssetsReleaseUrl/'
        'fonnx-ortextensions-$_ortExtensionsCommitShort-windows-x64.zip',
    sha256: '04d6571cf4c91b7bdf873adea18d2bf9495848603ba6a32b9bdd2f92c08af7d0',
    libraryEntrySuffix: 'ortextensions.dll',
  ),
};

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final os = input.config.code.targetOS;

    if (os == OS.fuchsia) {
      throw UnsupportedError('fonnx does not support ONNX Runtime on Fuchsia.');
    }

    final architecture = input.config.code.targetArchitecture;
    final key = '${os.name}-${architecture.name}';
    final artifact = _ortArtifacts[key];
    if (artifact == null) {
      throw UnsupportedError(
        'No fonnx ONNX Runtime artifact for $key. Supported targets: '
        '${_ortArtifacts.keys.join(', ')}. Intel macOS is intentionally not '
        'supported.',
      );
    }

    await _publishArtifact(
      input: input,
      output: output,
      artifact: artifact,
      outputFileName: os.dylibFileName('onnxruntime'),
      assetName: _ortAssetName,
    );

    final extensionsArtifact = _ortExtensionsArtifacts[key];
    if (extensionsArtifact != null) {
      await _publishArtifact(
        input: input,
        output: output,
        artifact: extensionsArtifact,
        outputFileName: os.dylibFileName('ortextensions'),
        assetName: _ortExtensionsAssetName,
      );
    }

    // Make changes to the hook invalidate hooks_runner's own dependency graph.
    output.dependencies.add(input.packageRoot.resolve('hook/build.dart'));
  });
}

Future<void> _publishArtifact({
  required BuildInput input,
  required BuildOutputBuilder output,
  required _Artifact artifact,
  required String outputFileName,
  required String assetName,
}) async {
  final cachedLibrary = await _ensureCachedLibrary(
    artifact: artifact,
    outputFileName: outputFileName,
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
}

Future<File> _ensureCachedLibrary({
  required _Artifact artifact,
  required String outputFileName,
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
      () => _ensureVerifiedDownload(artifact, archiveFile),
    );
    await _extractLibrary(artifact, archiveFile, library);
    return library;
  });
}

Future<void> _ensureVerifiedDownload(
  _Artifact artifact,
  File archiveFile,
) async {
  if (await archiveFile.exists()) {
    final digest = await _sha256Of(archiveFile);
    if (digest == artifact.sha256) return;
    await archiveFile.delete();
  }

  final partial = File('${archiveFile.path}.partial');
  if (await partial.exists()) await partial.delete();

  stderr.writeln('fonnx: downloading ${artifact.url}');
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
}

Future<void> _extractLibrary(
  _Artifact artifact,
  File archiveFile,
  File outputFile,
) async {
  stderr.writeln('fonnx: extracting ${p.basename(outputFile.path)}');
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
