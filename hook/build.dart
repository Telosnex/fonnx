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

const _nativeAssetsReleaseUrl =
    'https://github.com/Telosnex/fonnx/releases/download/'
    'native-assets-ort-1.27.0-ortx-fe4e13f-bpe-only-v2';
const _iosNativeAssetsUrl =
    '$_nativeAssetsReleaseUrl/'
    'fonnx-ios-arm64-ort-1.27.0-ortx-fe4e13f4.zip';

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
  'ios-arm64-iphoneos': _Artifact(
    url: _iosNativeAssetsUrl,
    sha256: 'dfa6edf1a35e0679070b69384191e0747f79dfef948edb7408eacdc2f417d510',
    libraryEntrySuffix: 'iphoneos/libonnxruntime.dylib',
  ),
  'ios-arm64-iphonesimulator': _Artifact(
    url: _iosNativeAssetsUrl,
    sha256: 'dfa6edf1a35e0679070b69384191e0747f79dfef948edb7408eacdc2f417d510',
    libraryEntrySuffix: 'iphonesimulator/libonnxruntime.dylib',
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

const _ortExtensionsArtifacts = <String, _Artifact>{
  'android-arm': _Artifact(
    url:
        '$_nativeAssetsReleaseUrl/'
        'fonnx-ortextensions-$_ortExtensionsCommitShort-android-arm.zip',
    sha256: '23fb7f372ed77386424584e14a7718674e05bc35ee76b74436527ebd88bddcdc',
    libraryEntrySuffix: 'libortextensions.so',
  ),
  'android-arm64': _Artifact(
    url:
        '$_nativeAssetsReleaseUrl/'
        'fonnx-ortextensions-$_ortExtensionsCommitShort-android-arm64.zip',
    sha256: 'ab796237516e98968d84d02772689d9d67ca1ba87ec088292332ba44671c5627',
    libraryEntrySuffix: 'libortextensions.so',
  ),
  'android-x64': _Artifact(
    url:
        '$_nativeAssetsReleaseUrl/'
        'fonnx-ortextensions-$_ortExtensionsCommitShort-android-x64.zip',
    sha256: '27c1ecd5673c57631d98bb6856a9684c820ae11e4117dd24a26dd4f4be22decf',
    libraryEntrySuffix: 'libortextensions.so',
  ),
  'ios-arm64-iphoneos': _Artifact(
    url: _iosNativeAssetsUrl,
    sha256: 'dfa6edf1a35e0679070b69384191e0747f79dfef948edb7408eacdc2f417d510',
    libraryEntrySuffix: 'iphoneos/libortextensions.dylib',
  ),
  'ios-arm64-iphonesimulator': _Artifact(
    url: _iosNativeAssetsUrl,
    sha256: 'dfa6edf1a35e0679070b69384191e0747f79dfef948edb7408eacdc2f417d510',
    libraryEntrySuffix: 'iphonesimulator/libortextensions.dylib',
  ),
  'linux-arm64': _Artifact(
    url:
        '$_nativeAssetsReleaseUrl/'
        'fonnx-ortextensions-$_ortExtensionsCommitShort-linux-arm64.zip',
    sha256: 'a4785c95de8a102362a9765c61a5f6cc01bedefbd1453d9667cd6345d719b0cf',
    libraryEntrySuffix: 'libortextensions.so',
  ),
  'linux-x64': _Artifact(
    url:
        '$_nativeAssetsReleaseUrl/'
        'fonnx-ortextensions-$_ortExtensionsCommitShort-linux-x64.zip',
    sha256: '6a7aa5a33926e797e205a6925fbbbfe26bb0314ff333886e5ad78f4383c3993b',
    libraryEntrySuffix: 'libortextensions.so',
  ),
  'macos-arm64': _Artifact(
    url:
        '$_nativeAssetsReleaseUrl/'
        'fonnx-ortextensions-$_ortExtensionsCommitShort-macos-arm64.zip',
    sha256: '92f03c220720a1a902283f6b720039d48335c4251138af78468a8e436cec2d9c',
    libraryEntrySuffix: 'libortextensions.dylib',
  ),
  'windows-arm64': _Artifact(
    url:
        '$_nativeAssetsReleaseUrl/'
        'fonnx-ortextensions-$_ortExtensionsCommitShort-windows-arm64.zip',
    sha256: '8fea38110b79c6b6777ae84e970e6b115674a855c9856659499f219e05e63e87',
    libraryEntrySuffix: 'ortextensions.dll',
  ),
  'windows-x64': _Artifact(
    url:
        '$_nativeAssetsReleaseUrl/'
        'fonnx-ortextensions-$_ortExtensionsCommitShort-windows-x64.zip',
    sha256: '8cd742345c48e3502b124f3b21bd06a0010ebe8a9ea33b021f2a082aa0691a5d',
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
    final sdkSuffix = os == OS.iOS
        ? switch (input.config.code.iOS.targetSdk) {
            IOSSdk.iPhoneOS => '-iphoneos',
            IOSSdk.iPhoneSimulator => '-iphonesimulator',
            final sdk => throw UnsupportedError('Unsupported iOS SDK: $sdk.'),
          }
        : '';
    final key = '${os.name}-${architecture.name}$sdkSuffix';
    final artifact = _ortArtifacts[key];
    if (artifact == null) {
      throw UnsupportedError(
        'No fonnx ONNX Runtime artifact for $key. Supported targets: '
        '${_ortArtifacts.keys.join(', ')}. Intel Apple targets are '
        'intentionally not supported.',
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
