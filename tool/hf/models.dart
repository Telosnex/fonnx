// The model files on Hugging Face (ADR 001): their pins in
// native_artifacts/manifest.json, and the runtime catalog made from the pins.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:fonnx/runtime_models.dart';
import 'package:kiln/kiln.dart';
import 'package:kiln/src/release_tool.dart' show runtimeFilesDart;
import 'package:kiln/src/runtime_file.dart' show validateFileName;

/// The Hugging Face repository with the model files.
const hfRepository = 'telosnex/fonnx';

/// The directory of the model files. Git does not track the ONNX files in it.
const modelRoot = 'example/assets/models';

const fonnxManifestPath = 'native_artifacts/manifest.json';
const catalogDartPath = 'lib/src/kiln.g.dart';

final _commitPattern = RegExp(r'^[0-9a-f]{40}$');
final _digestPattern = RegExp(r'^[0-9a-f]{64}$');

/// The URL of [name] in the Hugging Face commit [commit] (D2).
String hfUrl(String commit, String name) =>
    'https://huggingface.co/$hfRepository/resolve/$commit/$name';

/// Whether [url] is a Hugging Face URL pinned to a commit (I1).
bool isPinnedHfUrl(String url) => RegExp(
  '^https://huggingface\\.co/${RegExp.escape(hfRepository)}'
  r'/resolve/[0-9a-f]{40}/[^/]+$',
).hasMatch(url);

/// One model file: its pin in the manifest.
final class HfModel {
  HfModel({
    required this.path,
    required this.name,
    required this.sha256,
    required this.bytes,
    required this.commit,
  });

  /// The path in the package, below [modelRoot].
  final String path;

  /// The file name on Hugging Face.
  final String name;
  final String sha256;
  final int bytes;

  /// The Hugging Face commit with the file. Null before the first upload.
  String? commit;

  String get url => hfUrl(commit!, name);

  /// The path below [modelRoot].
  String get modelPath => path.substring(modelRoot.length + 1);

  File file(Directory root) => File('${root.path}/$path');

  RuntimeFile get runtimeFile =>
      RuntimeFile(name: name, sha256: sha256, bytes: bytes, url: url);
}

Future<Map<String, Object?>> readManifest(Directory root) async =>
    jsonDecode(await File('${root.path}/$fonnxManifestPath').readAsString())
        as Map<String, Object?>;

Future<void> writeManifest(Directory root, Map<String, Object?> manifest) =>
    File('${root.path}/$fonnxManifestPath').writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
    );

/// The model files of [manifest] that are on Hugging Face: each `models`
/// entry below [modelRoot]. Throws if an entry is not valid.
List<HfModel> hfModels(Map<String, Object?> manifest) {
  final models = manifest['models'];
  if (models is! Map<String, Object?>) {
    throw const FormatException('manifest: models must be an object');
  }
  final result = <HfModel>[];
  final names = <String>{};
  for (final MapEntry(:key, :value) in models.entries) {
    if (!key.startsWith('$modelRoot/')) continue;
    if (value is! Map<String, Object?>) {
      throw FormatException('$key must be an object');
    }
    final model = switch (value) {
      {
        'path': final String path,
        'name': final String name,
        'sha256': final String sha256,
        'bytes': final int bytes,
      }
          when path == key && bytes > 0 && _digestPattern.hasMatch(sha256) =>
        HfModel(
          path: path,
          name: name,
          sha256: sha256,
          bytes: bytes,
          commit: switch (value['commit']) {
            null => null,
            final String commit when _commitPattern.hasMatch(commit) => commit,
            _ => throw FormatException('$key: commit is not a commit hash'),
          },
        ),
      _ => throw FormatException(
        '$key needs path, name, sha256 and bytes (ADR 001 section 5)',
      ),
    };
    validateFileName(model.name);
    if (!names.add(model.name)) {
      throw FormatException('Two models have the name ${model.name}');
    }
    result.add(model);
  }
  return result;
}

/// Throws unless the names in the manifest are those of
/// [runtimeModelNamesByPath].
void checkRuntimeNames(List<HfModel> models) {
  final fromManifest = {for (final m in models) m.modelPath: m.name};
  if (fromManifest.length != runtimeModelNamesByPath.length ||
      fromManifest.entries.any(
        (e) => runtimeModelNamesByPath[e.key] != e.value,
      )) {
    throw StateError(
      'The models of $fonnxManifestPath and runtimeModelNamesByPath in '
      'lib/runtime_models.dart differ.',
    );
  }
}

/// Sets the commit of each model in [manifest] from [models].
void setCommits(Map<String, Object?> manifest, List<HfModel> models) {
  final entries = manifest['models']! as Map<String, Object?>;
  for (final model in models) {
    (entries[model.path]! as Map<String, Object?>)['commit'] = model.commit;
  }
}

/// The runtime catalog of [models], sorted by name. Each model needs a commit.
RuntimeFileSet catalog(List<HfModel> models) {
  final missing = [
    for (final model in models)
      if (model.commit == null) model.path,
  ];
  if (missing.isNotEmpty) {
    throw StateError('Not on Hugging Face yet: ${missing.join(', ')}');
  }
  return RuntimeFileSet(
    release: 'https://huggingface.co/$hfRepository',
    files: [for (final model in models) model.runtimeFile]
      ..sort((a, b) => a.name.compareTo(b.name)),
  );
}

/// The Dart source of [catalogDartPath] for [set].
String catalogDart(RuntimeFileSet set) => runtimeFilesDart(set);

/// The size and Git LFS SHA-256 of each file in [names] at [revision] on
/// Hugging Face. A file that is not there is not in the result.
Future<Map<String, (int, String?)>> hfFileInfo(
  String revision,
  Iterable<String> names,
) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(
      Uri.parse(
        'https://huggingface.co/api/models/$hfRepository/paths-info/$revision',
      ),
    );
    final token = Platform.environment['HF_TOKEN'];
    if (token != null && token.isNotEmpty) {
      request.headers.set('authorization', 'Bearer $token');
    }
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({'paths': names.toList()}));
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw HttpException(
        'Hugging Face paths-info $revision: ${response.statusCode} $body',
      );
    }
    return {
      for (final entry in (jsonDecode(body) as List).cast<Map>())
        entry['path'] as String: (
          entry['size'] as int,
          (entry['lfs'] as Map?)?['oid'] as String?,
        ),
    };
  } finally {
    client.close();
  }
}

/// Problems of [models] at their commits on Hugging Face: a file that is
/// missing, or that has another size or SHA-256 (I2). A file without Git LFS
/// data is downloaded and hashed.
Future<List<String>> hfProblems(List<HfModel> models) async {
  final problems = <String>[];
  final byCommit = <String, List<HfModel>>{};
  for (final model in models) {
    if (model.commit == null) {
      problems.add('${model.path} has no Hugging Face commit');
    } else {
      byCommit.putIfAbsent(model.commit!, () => []).add(model);
    }
  }
  for (final MapEntry(key: commit, value: group) in byCommit.entries) {
    final info = await hfFileInfo(commit, group.map((m) => m.name));
    for (final model in group) {
      final found = info[model.name];
      var sha256 = found?.$2;
      if (found != null && sha256 == null) {
        sha256 = await _downloadSha256(model.url);
      }
      if (found == null) {
        problems.add('${model.name} is not in Hugging Face commit $commit');
      } else if (found.$1 != model.bytes || sha256 != model.sha256) {
        problems.add(
          '${model.name} at $commit has ${found.$1} bytes and SHA-256 '
          '$sha256; ${model.path} pins ${model.bytes} and ${model.sha256}',
        );
      }
    }
  }
  return problems;
}

Future<String> _downloadSha256(String url) async {
  final client = HttpClient();
  try {
    final response = await (await client.getUrl(Uri.parse(url))).close();
    if (response.statusCode != 200) {
      throw HttpException('$url: ${response.statusCode}');
    }
    return '${await crypto.sha256.bind(response).first}';
  } finally {
    client.close();
  }
}
