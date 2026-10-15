// Graph surgery uses ONNX's Python tooling; orchestration stays in Dart.
// Usage: KOKORO_PYTHON=/path/to/python dart run tool/kokoro/prepare_streaming_models.dart
import 'dart:io';
import 'package:crypto/crypto.dart';

const revision = '234f60faa0eb388b01cdf7e60aca232af37aefda';
Future<void> main(List<String> args) async {
  final model = args.isEmpty
      ? 'example/assets/models/kokoro/onnx/model_uint8.onnx'
      : args[0];
  final out = args.length < 2
      ? 'example/assets/models/kokoro/onnx/stages'
      : args[1];
  final script = File('build/kokoro/split-kokoro-stages.py');
  await script.parent.create(recursive: true);
  final client = HttpClient();
  try {
    final response = await (await client.getUrl(
      Uri.parse(
        'https://raw.githubusercontent.com/moonshine-ai/moonshine/$revision/scripts/split-kokoro-stages.py',
      ),
    )).close();
    if (response.statusCode != 200) {
      throw HttpException('Source download failed: ${response.statusCode}');
    }
    final bytes = await response.fold<List<int>>([], (a, b) => a..addAll(b));
    if (sha256.convert(bytes).toString() !=
        '3c3b481588c85792055b55eb77b6d5fd890c9be4746c1770f72b1b7a4822acb3') {
      throw StateError('Unexpected split script hash');
    }
    await script.writeAsBytes(bytes);
  } finally {
    client.close();
  }
  final process = await Process.start(
    Platform.environment['KOKORO_PYTHON'] ?? 'python3',
    [script.path, model, '--out-dir', out, '--verify'],
    mode: ProcessStartMode.inheritStdio,
  );
  exitCode = await process.exitCode;
}
