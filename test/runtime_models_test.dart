import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fonnx/runtime_models.dart';
import 'package:native_prebuilt/runtime.dart';

void main() {
  test('runtime model map covers each example ONNX model', () async {
    final manifest =
        jsonDecode(await File('native_artifacts/manifest.json').readAsString())
            as Map<String, dynamic>;
    final models = (manifest['models'] as Map<String, dynamic>).keys
        .where(
          (path) =>
              path.startsWith('example/assets/models/') &&
              path.endsWith('.onnx'),
        )
        .map((path) => path.substring('example/assets/models/'.length))
        .toSet();

    expect(runtimeModelNamesByPath.keys.toSet(), models);
    expect(
      runtimeModelNamesByPath.values.toSet(),
      hasLength(runtimeModelNamesByPath.length),
      reason: 'runtimeRelease requires unique basenames',
    );
  });

  test('published model catalog matches the source pins', () async {
    final manifest =
        jsonDecode(await File('native_artifacts/manifest.json').readAsString())
            as Map<String, dynamic>;
    final models = manifest['models'] as Map<String, dynamic>;
    expect(
      nativePrebuiltRuntimeFiles.keys.toSet(),
      runtimeModelNamesByPath.values.toSet(),
    );
    for (final path in runtimeModelNamesByPath.keys) {
      final record =
          models['example/assets/models/$path'] as Map<String, dynamic>;
      final file = runtimeModelFile(path);
      expect(file.sha256, record['sha256']);
      expect(file.bytes, record['bytes']);
    }
  });

  test('FUTO model_fp32 release names are stable and distinct', () {
    expect(
      runtimeModelName('futoSwipe/honorable_sturgeon/model_fp32.onnx'),
      'futo_swipe_encoder_honorable_sturgeon.onnx',
    );
    expect(
      runtimeModelName(
        r'example\assets\models\futoSwipe\magic_macaw\model_fp32.onnx',
      ),
      'futo_swipe_decoder_magic_macaw.onnx',
    );
    expect(
      runtimeModelPath('futo_swipe_decoder_magic_macaw.onnx'),
      'futoSwipe/magic_macaw/model_fp32.onnx',
    );
  });

  test('unknown model and incomplete generated catalog fail closed', () {
    expect(() => runtimeModelName('missing.onnx'), throwsArgumentError);
    expect(
      () => runtimeModelFile('magika/magika.onnx', const {}),
      throwsStateError,
    );
  });

  test('download uses native_prebuilt verification', () async {
    final bytes = utf8.encode('verified ONNX test bytes');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) async {
      request.response
        ..statusCode = HttpStatus.ok
        ..contentLength = bytes.length
        ..add(bytes);
      await request.response.close();
    });
    final url = 'http://127.0.0.1:${server.port}/magika.onnx';
    final runtimeFile = RuntimeFile(
      name: runtimeModelName('magika/magika.onnx'),
      sha256: sha256.convert(bytes).toString(),
      bytes: bytes.length,
      url: url,
    );
    final output = await Directory.systemTemp.createTemp(
      'fonnx_runtime_model_test_',
    );
    addTearDown(() => output.delete(recursive: true));

    final file = await ensureFonnxRuntimeModel(
      'example/assets/models/magika/magika.onnx',
      output,
      runtimeFiles: {runtimeFile.name: runtimeFile},
    );

    expect(await file.readAsBytes(), bytes);
    expect(file.path, endsWith(runtimeFile.name));
  });
}
