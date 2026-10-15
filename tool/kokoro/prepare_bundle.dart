// Rebuild the unpublished English bundle from pinned upstream sources.
// KOKORO_PYTHON must have the versions documented in README.md.
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

const root = 'example/assets/models/kokoro';
const kokoroRevision = '1939ad2a8e416c0acfeecc08a694d14ef25f2231';
const fallbackRevision = 'a5631b285d18d59483c32c0c3379cb9fac924f4b';
const voices = [
  'af_alloy',
  'af_aoede',
  'af_bella',
  'af_heart',
  'af_jessica',
  'af_kore',
  'af_nicole',
  'af_nova',
  'af_river',
  'af_sarah',
  'af_sky',
  'am_adam',
  'am_echo',
  'am_eric',
  'am_fenrir',
  'am_liam',
  'am_michael',
  'am_onyx',
  'am_puck',
  'am_santa',
  'bf_alice',
  'bf_emma',
  'bf_isabella',
  'bf_lily',
  'bm_daniel',
  'bm_fable',
  'bm_george',
  'bm_lewis',
];

Future<void> main(List<String> args) async {
  if (args.any((a) => !['--record', '--tests'].contains(a))) {
    throw ArgumentError('Usage: prepare_bundle.dart [--tests] [--record]');
  }
  final record = args.contains('--record');
  final lockFile = File('tool/kokoro/artifacts.json');
  final Map<String, dynamic> pins = lockFile.existsSync()
      ? (jsonDecode(lockFile.readAsStringSync())
                as Map<String, dynamic>)['files']
            as Map<String, dynamic>
      : {};
  if (pins.isEmpty && !record) {
    throw StateError(
      'Missing artifact lock; use --record only when reviewing new artifacts',
    );
  }
  final python = Platform.environment['KOKORO_PYTHON'] ?? 'python3';
  await _run(python, [
    '-c',
    r'''
from importlib.metadata import version
expected = {'misaki':'0.9.4','spacy':'3.8.16','onnx':'1.23.2','torch':'2.14.1','transformers':'5.19.0','numpy':'2.5.4','en_core_web_sm':'3.8.0'}
for name,want in expected.items():
    got=version(name)
    if got != want: raise SystemExit(f'{name}: need {want}, got {got}')
''',
  ]);
  for (final dir in ['onnx', 'voices', 'spacy', 'misaki']) {
    Directory('$root/$dir').createSync(recursive: true);
  }
  final downloads = {
    'onnx/model_uint8.onnx': 'onnx/model_uint8.onnx',
    if (args.contains('--tests')) 'onnx/model.onnx': 'onnx/model.onnx',
    for (final voice in voices) 'voices/$voice.bin': 'voices/$voice.bin',
  };
  final client = HttpClient();
  try {
    for (final e in downloads.entries) {
      final file = File('$root/${e.key}');
      if (await file.exists() && await _matches(file, pins[e.key])) continue;
      final uri = Uri.parse(
        'https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX/resolve/$kokoroRevision/${e.value}',
      );
      final response = await (await client.getUrl(uri)).close();
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}', uri: uri);
      }
      final temporary = File('${file.path}.download');
      try {
        await response.pipe(temporary.openWrite());
        if (!record && !await _matches(temporary, pins[e.key])) {
          throw StateError('Hash mismatch: ${e.key}');
        }
        await temporary.rename(file.path);
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
    }
  } finally {
    client.close();
  }
  await _run(python, [
    '-c',
    r'''
import importlib.resources,shutil,sys
from pathlib import Path
for name in ['us_gold.json','us_silver.json','gb_gold.json','gb_silver.json']:
    with importlib.resources.as_file(importlib.resources.files('misaki.data')/name) as src:
        shutil.copyfile(src,Path(sys.argv[1])/'misaki'/name)
''',
    root,
  ]);
  await _run(python, ['tool/kokoro/export_spacy_en.py', '$root/spacy']);
  await _run(python, ['tool/kokoro/export_misaki_fallback.py', '$root/misaki']);
  await _run(Platform.resolvedExecutable, [
    'run',
    'tool/kokoro/prepare_streaming_models.dart',
  ]);
  final files = <String, dynamic>{};
  for (final path in [
    ...downloads.keys,
    'misaki/us_gold.json',
    'misaki/us_silver.json',
    'misaki/gb_gold.json',
    'misaki/gb_silver.json',
    'spacy/en_core_web_sm.json',
    'spacy/en_core_web_sm_tagger.bin',
    'misaki/g2p_fallback_en_us.onnx',
    'misaki/g2p_fallback_en_us.json',
    'onnx/stages/prosody.onnx',
    'onnx/stages/decoder.onnx',
  ]) {
    final f = File('$root/$path');
    final entry = {
      'sha256': '${await sha256.bind(f.openRead()).first}',
      'bytes': await f.length(),
      'license': path.startsWith('spacy/') ? 'MIT' : 'Apache-2.0',
    };
    if (!record && !await _matches(f, pins[path])) {
      throw StateError('Generated artifact differs: $path');
    }
    files[path] = entry;
  }
  if (record) {
    // This is a staging lock, not the published ADR 001 runtime catalog.
    lockFile.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert({'status': 'unpublished; license and speech-quality release reviews pending', 'kokoroRevision': kokoroRevision, 'fallbackRevision': fallbackRevision, 'moonshineRevision': '234f60faa0eb388b01cdf7e60aca232af37aefda', 'files': files})}\n',
    );
  }
  stdout.writeln(
    'Verified ${files.length} English artifacts. Publication remains a separate release step.',
  );
}

Future<bool> _matches(File file, dynamic pin) async =>
    pin is Map &&
    await file.length() == pin['bytes'] &&
    '${await sha256.bind(file.openRead()).first}' == pin['sha256'];
Future<void> _run(String executable, List<String> args) async {
  final p = await Process.start(
    executable,
    args,
    mode: ProcessStartMode.inheritStdio,
  );
  if (await p.exitCode != 0) {
    throw ProcessException(executable, args, 'Kokoro preparation failed');
  }
}
