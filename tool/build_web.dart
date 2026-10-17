/// Writes the generated FONNX web runtime files to --out: the ONNX Runtime
/// Web files of web_build/onnxruntime_web.json, extracted from the pinned npm
/// tarball, and the Kokoro Worker engine, compiled from Dart. The tarball and
/// each ORT file are checked by SHA-256.
///
/// The release workflow runs it (native_prebuilt ADR 002 D10). For a local
/// copy in lib/web/:
///
///     dart run tool/build_web.dart --out /tmp/fonnx_web
///     dart run native_prebuilt:web install-dev --from /tmp/fonnx_web
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const _usage = 'dart run tool/build_web.dart --out <dir>';

Future<void> main(List<String> args) async {
  final out = switch (args) {
    ['--out', final dir] => Directory(dir).absolute,
    ['-h' || '--help'] => _exit(_usage, 0),
    _ => _exit(_usage, 1),
  };
  final root = Directory.fromUri(Platform.script.resolve('..'));
  final pin = switch (jsonDecode(
    await File('${root.path}/web_build/onnxruntime_web.json').readAsString(),
  )) {
    {
      'npmTarball': final String url,
      'sha256': final String tarballSha256,
      'files': final List files,
    } =>
      (
        url: url,
        sha256: tarballSha256,
        files: [
          for (final file in files)
            switch (file) {
              {
                'entry': final String entry,
                'name': final String name,
                'sha256': final String sha256,
              } =>
                (entry: entry, name: name, sha256: sha256),
              _ => _exit('Malformed file in onnxruntime_web.json', 1),
            },
        ],
      ),
    _ => _exit('Malformed web_build/onnxruntime_web.json', 1),
  };

  if (await out.exists() && await out.list().isEmpty == false) {
    final names = {...pin.files.map((f) => f.name), _kokoroEngine};
    await for (final entity in out.list()) {
      if (!names.contains(entity.uri.pathSegments.lastWhere((s) => s != ''))) {
        _exit('--out holds other files: ${entity.path}', 1);
      }
    }
  }
  await out.create(recursive: true);

  final work = await Directory.systemTemp.createTemp('fonnx_build_web_');
  try {
    final tarball = File('${work.path}/onnxruntime-web.tgz');
    stdout.writeln('Downloading ${pin.url}');
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(pin.url));
      final response = await request.close();
      if (response.statusCode != 200) {
        _exit('HTTP ${response.statusCode} for ${pin.url}', 1);
      }
      await response.pipe(tarball.openWrite());
    } finally {
      client.close();
    }
    final tarballHash = '${await sha256.bind(tarball.openRead()).first}';
    if (tarballHash != pin.sha256) {
      _exit('Tarball SHA-256 $tarballHash, expected ${pin.sha256}', 1);
    }

    final result = await Process.run('tar', [
      '-xzf',
      tarball.path,
      '-C',
      work.path,
      for (final file in pin.files) file.entry,
    ]);
    if (result.exitCode != 0) _exit('tar failed: ${result.stderr}', 1);

    for (final file in pin.files) {
      final source = File('${work.path}/${file.entry}');
      final hash = '${await sha256.bind(source.openRead()).first}';
      if (hash != file.sha256) {
        _exit('${file.entry} SHA-256 $hash, expected ${file.sha256}', 1);
      }
      await source.copy('${out.path}/${file.name}');
      stdout.writeln('  $hash  ${file.name}');
    }
  } finally {
    await work.delete(recursive: true);
  }
  await _compileKokoroEngine(root, out);
}

/// The Dart program of the Kokoro Worker (fonnx ADR 002 D10).
const _kokoroEngine = 'kokoro_engine.dart.js';

Future<void> _compileKokoroEngine(Directory root, Directory out) async {
  final work = await Directory.systemTemp.createTemp('fonnx_kokoro_engine_');
  try {
    final compiled = '${work.path}/$_kokoroEngine';
    final result = await Process.run(Platform.resolvedExecutable, [
      'compile',
      'js',
      '-O2',
      '--no-source-maps',
      'lib/models/kokoro/web/kokoro_engine_worker.dart',
      '-o',
      compiled,
    ], workingDirectory: root.path);
    if (result.exitCode != 0) {
      _exit('dart compile js failed:\n${result.stdout}${result.stderr}', 1);
    }
    final file = await File(compiled).copy('${out.path}/$_kokoroEngine');
    stdout.writeln(
      '  ${await sha256.bind(file.openRead()).first}  $_kokoroEngine',
    );
  } finally {
    await work.delete(recursive: true);
  }
}

Never _exit(String message, int code) {
  (code == 0 ? stdout : stderr).writeln(message);
  exit(code);
}
