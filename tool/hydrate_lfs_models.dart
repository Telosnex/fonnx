import 'dart:convert';
import 'dart:io';

const _lfsPaths = [
  'docs/assets/models/miniLmL6V2/miniLmL6V2.onnx',
  'docs/assets/models/msmarcoMiniLmL6V3/msmarcoMiniLmL6V3.onnx',
  'docs/assets/models/whisper/whisper_tiny.onnx',
  'example/assets/models/miniLmL6V2/miniLmL6V2.onnx',
  'example/assets/models/minishLab/potion32m.onnx',
  'example/assets/models/msmarcoMiniLmL6V3/msmarcoMiniLmL6V3.onnx',
  'example/assets/models/pyannote/pyannote_seg3.onnx',
  'example/assets/models/whisper/whisper_tiny.onnx',
];

const _startMarker = '# fonnx CI LFS attributes: start';
const _endMarker = '# fonnx CI LFS attributes: end';
const _pointerPrefix = 'version https://git-lfs.github.com/spec/v1';

Future<void> main() async {
  final root = File.fromUri(Platform.script).parent.parent;
  final attributes = _gitPath(root, 'info/attributes');
  await attributes.parent.create(recursive: true);
  final existing = await attributes.exists()
      ? await attributes.readAsString()
      : '';
  final withoutPreviousBlock = existing.replaceAll(
    RegExp(
      '${RegExp.escape(_startMarker)}.*?${RegExp.escape(_endMarker)}\\n?',
      dotAll: true,
    ),
    '',
  );
  final block = [
    _startMarker,
    for (final path in _lfsPaths) '$path filter=lfs diff=lfs merge=lfs -text',
    _endMarker,
    '',
  ].join('\n');
  await attributes.writeAsString('$withoutPreviousBlock$block');

  final process = await Process.start(
    'git',
    ['lfs', 'pull', '--include=${_lfsPaths.join(',')}'],
    workingDirectory: root.path,
    mode: ProcessStartMode.inheritStdio,
  );
  final exitCode = await process.exitCode;
  if (exitCode != 0) {
    throw ProcessException('git', const ['lfs', 'pull'], '', exitCode);
  }

  for (final relativePath in _lfsPaths) {
    final file = File('${root.path}/$relativePath');
    if (!await file.exists()) throw StateError('Missing $relativePath');
    final prefix = await file
        .openRead(0, (await file.length()).clamp(0, 200))
        .fold<List<int>>(<int>[], (bytes, chunk) => bytes..addAll(chunk));
    if (utf8.decode(prefix, allowMalformed: true).startsWith(_pointerPrefix)) {
      throw StateError('Git LFS did not hydrate $relativePath');
    }
  }
  stdout.writeln('PASS: hydrated ${_lfsPaths.length} Git LFS model paths');
}

File _gitPath(Directory root, String path) {
  final result = Process.runSync('git', [
    'rev-parse',
    '--git-path',
    path,
  ], workingDirectory: root.path);
  if (result.exitCode != 0) {
    throw ProcessException(
      'git',
      ['rev-parse', '--git-path', path],
      '${result.stderr}',
      result.exitCode,
    );
  }
  final value = '${result.stdout}'.trim();
  return File(value.startsWith('/') ? value : '${root.path}/$value');
}
