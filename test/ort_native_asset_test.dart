import 'dart:ffi';

import 'package:flutter_test/flutter_test.dart';
import 'package:fonnx/onnx/ort.dart';
import 'package:fonnx/onnx/ort_ffi_bindings.dart';

void main() {
  test('bundled ONNX Runtime exports a usable C API', () {
    final apiBase = OrtGetApiBase();
    expect(apiBase, isNot(nullptr));
    expect(apiBase.ref.GetApi, isNot(nullptr));
  });

  test('bundled ONNX Runtime creates a core-only model session', () {
    final session = createOrtSession('test/models/magika.onnx');
    expect(session.sessionPtr.value, isNot(nullptr));
    releaseOrtSessionObjects(session);
  });
}
