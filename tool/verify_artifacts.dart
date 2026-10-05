import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:native_prebuilt/native_prebuilt.dart';
import 'package:native_prebuilt/src/release_tool.dart';
import '../hook/upstream_ort.dart';
import 'futo/bundle.dart';

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
  'linux': 'glibc 2.35 and Ubuntu 22.04 libstdc++',
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
      manifest['profile'] != 2 ||
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

  final native = (await PrebuiltManifest.load(root.uri))!;
  _expectKeys(native.targets.keys.toSet(), _nativeTargets, 'native target');
  final upstream = await loadUpstreamOrt(root.uri);
  for (final target in native.targets.entries) {
    _expectKeys(target.value.files.map((f) => f.asset!).toSet(), const {
      ortAsset,
      extensionsAsset,
      finalizerAsset,
    }, target.key);
    final ort = target.value.files.singleWhere((f) => f.asset == ortAsset);
    if (jsonEncode(ort.toJson()) !=
        jsonEncode(upstream[target.key]!.toJson())) {
      throw FormatException(
        '${target.key} no longer uses its pinned upstream ORT file',
      );
    }
  }

  await _verifyLocalRecords(
    root,
    _object(manifest['webAssets'], 'webAssets'),
    expectedCount: 21,
    label: 'canonical Web asset',
  );
  await _verifyLocalRecords(
    root,
    _object(manifest['publishedWebAssets'], 'publishedWebAssets'),
    expectedCount: 21,
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
    expectedCount: 18,
    label: 'model',
    rejectLfsPointers: true,
  );

  await verifyFutoSwipeBundle(
    Directory('${root.path}/example/assets/models/futoSwipe'),
  );
  await _verifyWebRuntime(root);
  final problems = await checkPackage(
    packageRoot: root.uri,
    download: arguments.contains('--downloads'),
    log: stdout.writeln,
  );
  if (problems.isNotEmpty) throw StateError(problems.join('\n'));
  stdout.writeln(
    'PASS: ${native.targets.length} native targets, 35 Web assets, 18 model fixtures, '
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
    if (actualBytes != expectedBytes) {
      throw StateError(
        'Size mismatch for $relativePath: expected $expectedBytes, got $actualBytes',
      );
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
  final webPackage = _object(
    jsonDecode(
      await File('${root.path}/example/web/package.json').readAsString(),
    ),
    'example/web/package.json',
  );
  if (webPackage['type'] != 'module') {
    throw const FormatException('example/web must declare ES module semantics');
  }
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
  for (final canonical
      in Directory(
        '${root.path}/example/web',
      ).listSync().whereType<File>().where(
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
