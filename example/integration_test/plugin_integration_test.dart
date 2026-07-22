import 'dart:ffi';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fonnx/models/minishLab/minish_lab.dart';
import 'package:fonnx/onnx/ort.dart';
import 'package:fonnx/onnx/ort_ffi_bindings.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('bundled ONNX Runtime is callable', (_) async {
    final apiBase = OrtGetApiBase();
    expect(apiBase, isNot(nullptr));
    expect(apiBase.ref.GetApi, isNot(nullptr));
  });

  testWidgets('Dart FFI isolate runs a real embedding model', (_) async {
    final modelData = await rootBundle.load(
      'assets/models/minishLab/potion8m.onnx',
    );
    final tempDirectory = await Directory.systemTemp.createTemp('fonnx-model-');
    final modelFile = File('${tempDirectory.path}/potion8m.onnx');
    try {
      await modelFile.writeAsBytes(modelData.buffer.asUint8List(), flush: true);
      final model = MinishLab.load(modelFile.path);
      final tokens =
          MinishLab.potion8mTokenizer
              .tokenize('native assets use one Dart FFI implementation')
              .single
              .tokens;
      final embedding = await model.getEmbeddingAsVector(tokens);
      expect(embedding, hasLength(256));
    } finally {
      await tempDirectory.delete(recursive: true);
    }
  });

  testWidgets('bundled Extensions registers Whisper BpeDecoder', (_) async {
    final modelData = await rootBundle.load('assets/models/bpe_decoder.onnx');
    final tempDirectory = await Directory.systemTemp.createTemp('fonnx-smoke-');
    final modelFile = File('${tempDirectory.path}/bpe_decoder.onnx');
    try {
      await modelFile.writeAsBytes(modelData.buffer.asUint8List(), flush: true);
      final session = createOrtSession(
        modelFile.path,
        includeOnnxExtensionsOps: true,
      );
      expect(session.sessionPtr.value, isNot(nullptr));
      releaseOrtSessionObjects(session);
    } finally {
      await tempDirectory.delete(recursive: true);
    }
  });
}
