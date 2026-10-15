import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:native_prebuilt/native_prebuilt.dart';
import 'package:native_prebuilt/src/release_tool.dart';
import '../hook/upstream_ort.dart';
import 'futo/bundle.dart';
import 'hf/models.dart';

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
  'webVersion': '1.27.0',
  'webTarballSha256':
      'b59c9819434a7519f334f77e8d4bf22b69808d531a57724cabc4bb2c0704c835',
};

/// The number of entries of the models section on Hugging Face.
const _expectedHfModels = 60;

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
      finalizerAsset,
    }, target.key);
    final ort = target.value.files.singleWhere((f) => f.asset == ortAsset);
    final pinned = upstream[target.key]!;
    if (ort.sha256 != pinned.sha256 ||
        (!target.key.startsWith('ios-') &&
            jsonEncode(ort.toJson()) != jsonEncode(pinned.toJson()))) {
      throw FormatException(
        '${target.key} no longer uses its pinned upstream ORT file',
      );
    }
  }

  for (final key in const ['webAssets', 'publishedWebAssets']) {
    if (manifest.containsKey(key)) {
      throw FormatException(
        '$key: the package web files belong in native_artifacts/web.json '
        '(native_prebuilt ADR 002). native_prebuilt:check verifies them.',
      );
    }
  }
  await _verifyLocalRecords(
    root,
    _object(manifest['deployedWebAssets'], 'deployedWebAssets'),
    expectedCount: 16,
    label: 'deployed Web asset',
  );
  final models = await _verifyModels(
    root,
    manifest,
    native,
    downloads: arguments.contains('--downloads'),
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
    'PASS: ${native.targets.length} native targets, 16 deployed Web assets, '
    '${models.length} models on Hugging Face, web.json, '
    'and exact source/profile pins',
  );
}

void _verifySources(Map<String, Object?> sources) {
  final ort = _object(sources['onnxRuntime'], 'sources.onnxRuntime');
  final web = _object(sources['onnxRuntimeWeb'], 'sources.onnxRuntimeWeb');
  if (ort['version'] != _expectedSources['ortVersion'] ||
      ort['commit'] != _expectedSources['ortCommit'] ||
      sources.containsKey('onnxRuntimeExtensions') ||
      web['version'] != _expectedSources['webVersion'] ||
      web['sha256'] != _expectedSources['webTarballSha256'] ||
      web['npmTarball'] !=
          'https://registry.npmjs.org/onnxruntime-web/-/onnxruntime-web-1.27.0.tgz') {
    throw const FormatException('Unexpected source pins');
  }
}

/// The checks of ADR 001: the pins of the models on Hugging Face (I1, I3),
/// the catalog made from them, the local copies that exist, and, with
/// [downloads], the files on Hugging Face (I2). The other entries of the
/// models section are test fixtures in Git.
Future<List<HfModel>> _verifyModels(
  Directory root,
  Map<String, Object?> manifest,
  PrebuiltManifest native, {
  required bool downloads,
}) async {
  final models = hfModels(manifest);
  if (models.length != _expectedHfModels) {
    throw FormatException(
      'Expected $_expectedHfModels models on Hugging Face, got ${models.length}',
    );
  }
  checkRuntimeNames(models);
  final records = _object(manifest['models'], 'models');
  await _verifyLocalRecords(
    root,
    {
      for (final entry in records.entries)
        if (!entry.key.startsWith('$modelRoot/')) entry.key: entry.value,
    },
    expectedCount: 1,
    label: 'test fixture',
  );

  final set = catalog(models);
  final actual = native.runtimeFiles;
  if (actual == null ||
      jsonEncode(actual.toJson()) != jsonEncode(set.toJson()) ||
      await File('${root.path}/$catalogDartPath').readAsString() !=
          catalogDart(set)) {
    throw StateError(
      'The runtime catalog differs from the models of $fonnxManifestPath. '
      'Run dart run tool/publish_models.dart.',
    );
  }
  for (final file in set.files) {
    if (!isPinnedHfUrl(file.url)) {
      throw StateError('${file.name}: ${file.url} is not pinned to a commit');
    }
  }

  final tracked = await Process.run('git', [
    'ls-files',
    '--',
    modelRoot,
  ], workingDirectory: root.path);
  if (tracked.exitCode != 0) throw StateError('git ls-files failed');
  final trackedModels = '${tracked.stdout}'
      .split('\n')
      .where((path) => path.toLowerCase().endsWith('.onnx'))
      .toList();
  if (trackedModels.isNotEmpty) {
    throw StateError(
      'Git tracks model files (ADR 001 I3): ${trackedModels.join(', ')}',
    );
  }

  // Local copies are optional: tool/fetch_hf_models.dart downloads them.
  for (final model in models) {
    final file = model.file(root);
    if (!await file.exists()) continue;
    if (await file.length() != model.bytes ||
        '${await sha256.bind(file.openRead()).first}' != model.sha256) {
      throw StateError(
        '${model.path} differs from its pin. '
        'Run dart run tool/fetch_hf_models.dart.',
      );
    }
  }

  if (downloads) {
    final problems = await hfProblems(models);
    if (problems.isNotEmpty) throw StateError(problems.join('\n'));
  }
  return models;
}

Future<void> _verifyLocalRecords(
  Directory root,
  Map<String, Object?> records, {
  required int expectedCount,
  required String label,
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
    final actualHash = await sha256.bind(file.openRead()).first;
    if (actualHash.toString() != expectedHash) {
      throw StateError(
        'Hash mismatch for $relativePath: expected $expectedHash, got $actualHash',
      );
    }
  }
}

Future<void> _verifyWebRuntime(Directory root) async {
  List<File> files(String directory, bool Function(String name) test) => [
    for (final file in Directory(
      '${root.path}/$directory',
    ).listSync().whereType<File>())
      if (test(file.uri.pathSegments.last)) file,
  ];

  // The package files: the hook installs them (ADR 002). Each Worker loads
  // ORT with the version query of its own URL.
  for (final file in files('lib/web', (n) => n.endsWith('_init.js'))) {
    final source = await file.readAsString();
    if (!source.contains('FonnxWorkerRpc') || source.contains('Math.random')) {
      throw StateError('${file.path} bypasses the fatal-safe Worker RPC');
    }
  }
  for (final file in files('lib/web', (n) => n.endsWith('_worker.js'))) {
    final source = await file.readAsString();
    if (source.contains('cdn.jsdelivr.net') ||
        source.contains('onnxruntime-web@') ||
        !source.contains(r'import(`./ort.min.mjs${query}`)') ||
        !source.contains('earlyMessages') ||
        !source.contains('protocolVersion') ||
        !source.contains('!== 1')) {
      throw StateError(
        '${file.path} does not use the pinned local ORT runtime',
      );
    }
  }

  // The deployed demo in docs/ keeps its own copies.
  for (final file in files(
    'docs',
    (n) => n.startsWith('fonnx_') && n.endsWith('_init.js'),
  )) {
    final source = await file.readAsString();
    if (!source.contains('FonnxWorkerRpc') || source.contains('Math.random')) {
      throw StateError('${file.path} bypasses the fatal-safe Worker RPC');
    }
  }
  for (final file in files(
    'docs',
    (n) => n.startsWith('fonnx_') && n.endsWith('_worker.js'),
  )) {
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
  final pin = _object(
    jsonDecode(
      await File('${root.path}/web_build/onnxruntime_web.json').readAsString(),
    ),
    'web_build/onnxruntime_web.json',
  );
  for (final raw in pin['files']! as List<Object?>) {
    final entry = _object(raw, 'onnxruntime_web.json file');
    final deployed = File('${root.path}/docs/${entry['name']}');
    if ('${await sha256.bind(deployed.openRead()).first}' != entry['sha256']) {
      throw StateError(
        'Deployed ${entry['name']} differs from the pinned ORT Web file',
      );
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
