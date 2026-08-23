import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const _nativeTargets = {
  'android-arm',
  'android-arm64',
  'android-x64',
  'ios-arm64-iphoneos',
  'ios-arm64-iphonesimulator',
  'linux-arm64',
  'linux-x64',
  'macos-arm64',
  'windows-arm64',
  'windows-x64',
};

const _expectedSources = {
  'ortVersion': '1.27.0',
  'ortCommit': '8f0278c77bf44b0cc83c098c6c722b92a36ac4b5',
  'ortxCommit': 'fe4e13f46b19fb490c90b09fe280277308bd5bb7',
  'webVersion': '1.27.0',
  'webTarballSha256':
      'b59c9819434a7519f334f77e8d4bf22b69808d531a57724cabc4bb2c0704c835',
};

const _expectedRuntimeConstraints = {
  'android': 'API 24',
  'ios': '15.1',
  'macos': '14.0, Apple Silicon',
  'linux': 'glibc 2.38 and GLIBCXX_3.4.32 (current Extensions producer)',
  'windows': 'Windows 10 plus Microsoft Visual C++ 2015-2022 runtime',
  'web': 'WebAssembly SIMD; threads require cross-origin isolation',
};

Future<void> main(List<String> arguments) async {
  if (arguments.any((argument) => argument != '--downloads')) {
    throw const FormatException(
      'Usage: dart run tool/verify_artifacts.dart [--downloads]',
    );
  }
  final root = File.fromUri(Platform.script).parent.parent;
  final manifestFile = File('${root.path}/native_artifacts/manifest.json');
  final manifest = _object(
    jsonDecode(await manifestFile.readAsString()),
    'manifest',
  );
  if (manifest['schema'] != 1 ||
      manifest['profile'] != 1 ||
      manifest['finalizerAbi'] != 1 ||
      manifest['webWorkerProtocolAbi'] != 1) {
    throw const FormatException('Unsupported manifest/profile/finalizer ABI');
  }
  _verifySources(_object(manifest['sources'], 'sources'));
  final constraints = _object(
    manifest['runtimeConstraints'],
    'runtimeConstraints',
  );
  _expectKeys(
    constraints.keys.toSet(),
    _expectedRuntimeConstraints.keys.toSet(),
    'runtime constraint',
  );
  for (final entry in _expectedRuntimeConstraints.entries) {
    if (constraints[entry.key] != entry.value) {
      throw FormatException('Unexpected ${entry.key} runtime constraint');
    }
  }

  final native = _object(manifest['nativeArtifacts'], 'nativeArtifacts');
  _expectKeys(native.keys.toSet(), _nativeTargets, 'native target');
  final downloads = <String, ({Uri url, String sha256})>{};
  for (final target in native.entries) {
    final record = _object(target.value, target.key);
    _expectKeys(record.keys.toSet(), const {
      'onnxRuntime',
      'extensions',
    }, target.key);
    for (final component in record.entries) {
      final artifact = _object(
        component.value,
        '${target.key}.${component.key}',
      );
      final url = artifact['url'];
      final digest = artifact['sha256'];
      final suffix = artifact['libraryEntrySuffix'];
      if (url is! String ||
          !url.startsWith('https://') ||
          url.contains('/latest/') ||
          digest is! String ||
          !_isDigest(digest) ||
          suffix is! String ||
          suffix.isEmpty ||
          suffix.contains('..')) {
        throw FormatException(
          'Invalid artifact: ${target.key}.${component.key}',
        );
      }
      final previous = downloads[digest];
      if (previous != null && previous.url.toString() != url) {
        throw FormatException('Digest $digest is assigned to multiple URLs');
      }
      downloads[digest] = (url: Uri.parse(url), sha256: digest);
    }
  }

  await _verifyLocalRecords(
    root,
    _object(manifest['webAssets'], 'webAssets'),
    expectedCount: 19,
    label: 'canonical Web asset',
  );
  await _verifyLocalRecords(
    root,
    _object(manifest['publishedWebAssets'], 'publishedWebAssets'),
    expectedCount: 19,
    label: 'published Web asset',
  );
  await _verifyLocalRecords(
    root,
    _object(manifest['deployedWebAssets'], 'deployedWebAssets'),
    expectedCount: 16,
    label: 'deployed Web asset',
  );
  await _verifyLocalRecords(
    root,
    _object(manifest['models'], 'models'),
    expectedCount: 14,
    label: 'model',
    rejectLfsPointers: true,
  );

  await _verifyWebRuntime(root);
  if (arguments.contains('--downloads')) {
    for (final artifact in downloads.values) {
      await _verifyDownload(artifact.url, artifact.sha256);
    }
  }
  stdout.writeln(
    'PASS: ${native.length} native targets, 35 Web assets, 14 model fixtures, '
    'and exact source/profile pins',
  );
}

void _verifySources(Map<String, Object?> sources) {
  final ort = _object(sources['onnxRuntime'], 'sources.onnxRuntime');
  final ortx = _object(
    sources['onnxRuntimeExtensions'],
    'sources.onnxRuntimeExtensions',
  );
  final web = _object(sources['onnxRuntimeWeb'], 'sources.onnxRuntimeWeb');
  final operators = ortx['operators'];
  if (ort['version'] != _expectedSources['ortVersion'] ||
      ort['commit'] != _expectedSources['ortCommit'] ||
      ortx['commit'] != _expectedSources['ortxCommit'] ||
      operators is! List ||
      operators.length != 1 ||
      operators.single != 'ai.onnx.contrib:BpeDecoder' ||
      web['version'] != _expectedSources['webVersion'] ||
      web['sha256'] != _expectedSources['webTarballSha256'] ||
      web['npmTarball'] !=
          'https://registry.npmjs.org/onnxruntime-web/-/onnxruntime-web-1.27.0.tgz') {
    throw const FormatException(
      'Unexpected source pins or selected-op inventory',
    );
  }
}

Future<void> _verifyLocalRecords(
  Directory root,
  Map<String, Object?> records, {
  required int expectedCount,
  required String label,
  bool rejectLfsPointers = false,
}) async {
  if (records.length != expectedCount) {
    throw FormatException(
      'Expected $expectedCount ${label}s, got ${records.length}',
    );
  }
  for (final entry in records.entries) {
    final record = _object(entry.value, entry.key);
    final relativePath = record['path'];
    final expectedHash = record['sha256'];
    final expectedBytes = record['bytes'];
    if (entry.key != relativePath ||
        relativePath is! String ||
        expectedHash is! String ||
        !_isDigest(expectedHash) ||
        expectedBytes is! int ||
        expectedBytes <= 0) {
      throw FormatException('Invalid $label record: ${entry.key}');
    }
    final file = File('${root.path}/$relativePath');
    if (!await file.exists()) throw StateError('Missing $label: $relativePath');
    final actualBytes = await file.length();
    if (actualBytes != expectedBytes) {
      throw StateError(
        'Size mismatch for $relativePath: expected $expectedBytes, got $actualBytes',
      );
    }
    if (rejectLfsPointers) {
      final prefix = await file
          .openRead(0, actualBytes.clamp(0, 200))
          .fold<List<int>>(<int>[], (bytes, chunk) => bytes..addAll(chunk));
      if (utf8
          .decode(prefix, allowMalformed: true)
          .startsWith('version https://git-lfs.github.com/spec/v1')) {
        throw StateError('$relativePath is an unhydrated Git LFS pointer');
      }
    }
    final actualHash = await sha256.bind(file.openRead()).first;
    if (actualHash.toString() != expectedHash) {
      throw StateError(
        'Hash mismatch for $relativePath: expected $expectedHash, got $actualHash',
      );
    }
  }
}

Future<void> _verifyWebRuntime(Directory root) async {
  final initFiles = <File>[
    ...Directory('${root.path}/example/web').listSync().whereType<File>().where(
      (file) => file.path.endsWith('_init.js'),
    ),
    ...Directory('${root.path}/docs').listSync().whereType<File>().where(
      (file) =>
          file.uri.pathSegments.last.startsWith('fonnx_') &&
          file.path.endsWith('_init.js'),
    ),
  ];
  for (final file in initFiles) {
    final source = await file.readAsString();
    if (!source.contains('FonnxWorkerRpc') || source.contains('Math.random')) {
      throw StateError('${file.path} bypasses the fatal-safe Worker RPC');
    }
  }
  final workerFiles = <File>[
    ...Directory('${root.path}/example/web').listSync().whereType<File>().where(
      (file) => file.path.endsWith('_worker.js'),
    ),
    ...Directory('${root.path}/docs').listSync().whereType<File>().where(
      (file) =>
          file.uri.pathSegments.last.startsWith('fonnx_') &&
          file.path.endsWith('_worker.js'),
    ),
  ];
  for (final file in workerFiles) {
    final source = await file.readAsString();
    if (source.contains('cdn.jsdelivr.net') ||
        source.contains('onnxruntime-web@') ||
        !source.contains("from './ort.min.mjs'") ||
        !source.contains('protocolVersion') ||
        !source.contains('!== 1')) {
      throw StateError(
        '${file.path} does not use the pinned local ORT runtime',
      );
    }
  }
  for (final name in const [
    'ort.min.mjs',
    'ort-wasm-simd-threaded.mjs',
    'ort-wasm-simd-threaded.wasm',
  ]) {
    final canonical = File('${root.path}/example/web/$name');
    final deployed = File('${root.path}/docs/$name');
    if (await sha256.bind(canonical.openRead()).first !=
        await sha256.bind(deployed.openRead()).first) {
      throw StateError('Deployed $name differs from the canonical asset');
    }
  }
  for (final canonical in Directory('${root.path}/example/web')
      .listSync()
      .whereType<File>()
      .where(
        (file) =>
            file.path.endsWith('.js') ||
            file.path.endsWith('.mjs') ||
            file.path.endsWith('.wasm'),
      )) {
    final published = File(
      '${root.path}/lib/web/${canonical.uri.pathSegments.last}',
    );
    if (!await published.exists() ||
        await sha256.bind(canonical.openRead()).first !=
            await sha256.bind(published.openRead()).first) {
      throw StateError('${canonical.path} differs from its published copy');
    }
  }
  final serviceWorker = await File(
    '${root.path}/docs/flutter_service_worker.js',
  ).readAsString();
  for (final obsolete in const [
    'ort-wasm-threaded.wasm',
    'ort-wasm-simd.jsep.wasm',
    'ort-wasm-simd.wasm',
    'ort-wasm.wasm',
  ]) {
    if (serviceWorker.contains('"$obsolete"')) {
      throw StateError('Service Worker still caches obsolete $obsolete');
    }
  }
}

Future<void> _verifyDownload(Uri url, String expectedHash) async {
  stdout.writeln('downloading $url');
  final client = HttpClient();
  try {
    final request = await client.getUrl(url);
    request.headers.set(
      HttpHeaders.userAgentHeader,
      'fonnx-artifact-verifier/1',
    );
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('HTTP ${response.statusCode}', uri: url);
    }
    final actual = await sha256.bind(response).first;
    if (actual.toString() != expectedHash) {
      throw StateError(
        'Hash mismatch for $url: expected $expectedHash, got $actual',
      );
    }
  } finally {
    client.close(force: true);
  }
}

Map<String, Object?> _object(Object? value, String label) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$label must be an object');
  }
  return value;
}

void _expectKeys(Set<String> actual, Set<String> expected, String label) {
  if (actual.length != expected.length || !actual.containsAll(expected)) {
    throw FormatException('Unexpected $label set: $actual');
  }
}

bool _isDigest(String value) => RegExp(r'^[0-9a-f]{64}$').hasMatch(value);
