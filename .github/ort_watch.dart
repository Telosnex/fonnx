// The upstream watch of ONNX Runtime: the `run` source in upstream.yaml.
//
// fonnx takes ONNX Runtime from three places: GitHub releases (desktop, and
// the source of the iOS build), Maven Central (Android) and npm (web). The
// update procedure (onnx_runtime/updating.md) takes the newest version that
// is on all three, so that is the update here. A newer GitHub release that
// Maven or npm does not have yet waits, but alerts after [maxWaitDays]:
// some releases never reach npm (1.31.0 did not).
//
// Like the default of a `tags` source, a patch release of the pinned minor
// version does not alert.
//
// Exit 0: up to date; 1: an update, or a release that waited too long;
// 2: an error.

import 'dart:convert';
import 'dart:io';

const maxWaitDays = 14;
const pinFile = 'native_artifacts/upstream_ort.json';
const releasesUrl =
    'https://api.github.com/repos/microsoft/onnxruntime/releases?per_page=50';
const mavenUrl =
    'https://repo.maven.apache.org/maven2/com/microsoft/onnxruntime/'
    'onnxruntime-android/maven-metadata.xml';
const npmUrl = 'https://registry.npmjs.org/onnxruntime-web';

final _stable = RegExp(r'^\d+\.\d+\.\d+$');

Future<void> main() async {
  try {
    exit(await check());
  } on Object catch (e) {
    stdout.writeln('Error: $e');
    exit(2);
  }
}

Future<int> check() async {
  final pin =
      (jsonDecode(File(pinFile).readAsStringSync()) as Map)['version']
          as String;

  final token = Platform.environment['GITHUB_TOKEN'];
  final releases = <String, DateTime>{}; // version -> published
  for (final r
      in jsonDecode(
            await get(releasesUrl, {
              'accept': 'application/vnd.github+json',
              if (token != null && token.isNotEmpty)
                'authorization': 'Bearer $token',
            }),
          )
          as List) {
    final m = r as Map;
    final version = (m['tag_name'] as String).replaceFirst('v', '');
    if (m['draft'] == true || m['prerelease'] == true) continue;
    if (!_stable.hasMatch(version) || m['published_at'] == null) continue;
    releases[version] = DateTime.parse(m['published_at'] as String);
  }
  final maven = {
    for (final m in RegExp(
      r'<version>([^<]+)</version>',
    ).allMatches(await get(mavenUrl)))
      m[1]!,
  };
  final npm =
      ((jsonDecode(
                    await get(npmUrl, {
                      // The short form: versions, without the readme.
                      'accept': 'application/vnd.npm.install-v1+json',
                    }),
                  )
                  as Map)['versions']
              as Map)
          .keys
          .toSet();
  if (releases.isEmpty || maven.isEmpty || npm.isEmpty) {
    throw StateError(
      'no versions (GitHub ${releases.length}, Maven ${maven.length}, '
      'npm ${npm.length}).',
    );
  }

  final newer = releases.keys.where((v) => compareMinor(v, pin) > 0).toList()
    ..sort(compare);
  if (newer.isEmpty) {
    stdout.writeln('Pinned $pin; no newer minor release on GitHub.');
    return 0;
  }
  final ready = newer.where((v) => maven.contains(v) && npm.contains(v));
  if (ready.isNotEmpty) {
    stdout.writeln(
      'Pinned $pin; ${ready.last} is on GitHub, Maven and npm. '
      'See onnx_runtime/updating.md.',
    );
    return 1;
  }
  final now = DateTime.now().toUtc();
  final lines = [
    for (final v in newer.reversed)
      '$v: on GitHub ${now.difference(releases[v]!).inDays} day(s); '
          'not on ${[if (!maven.contains(v)) 'Maven', if (!npm.contains(v)) 'npm'].join(' or ')}.',
  ];
  final overdue = now.difference(releases[newer.first]!).inDays > maxWaitDays;
  stdout.writeln(
    'Pinned $pin; ${overdue ? 'a release waited more than $maxWaitDays '
              'days for Maven or npm' : 'waiting for Maven or npm'}.',
  );
  lines.forEach(stdout.writeln);
  return overdue ? 1 : 0;
}

Future<String> get(String url, [Map<String, String> headers = const {}]) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  try {
    final request = await client.getUrl(Uri.parse(url));
    headers.forEach(request.headers.set);
    request.headers.set('user-agent', 'fonnx-upstream-watch');
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode} for $url');
    }
    return body;
  } finally {
    client.close();
  }
}

List<int> parts(String v) => v.split('.').map(int.parse).toList();

int compare(String a, String b) {
  final x = parts(a), y = parts(b);
  for (var i = 0; i < 3; i++) {
    if (x[i] != y[i]) return x[i].compareTo(y[i]);
  }
  return 0;
}

/// Compares the major and minor numbers only.
int compareMinor(String a, String b) {
  final x = parts(a), y = parts(b);
  return x[0] != y[0] ? x[0].compareTo(y[0]) : x[1].compareTo(y[1]);
}
