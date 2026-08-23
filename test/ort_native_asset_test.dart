import 'dart:ffi';

import 'package:flutter_test/flutter_test.dart';
import 'package:fonnx/onnx/ort.dart';
import 'package:fonnx/onnx/ort_ffi_bindings.dart';

void main() {
  test('package-owned finalizer ABI is explicit', () {
    expect(fonnxOrtSessionFinalizerAbiVersion(), 1);
    expect(
      fonnxOrtSessionFinalizerBuildInfo,
      'fonnx ORT session finalizer ABI 1',
    );
  });

  test('bundled ONNX Runtime exports a usable C API', () {
    final apiBase = OrtGetApiBase();
    expect(apiBase, isNot(nullptr));
    expect(apiBase.ref.GetApi, isNot(nullptr));
  });

  test('bundled ONNX Runtime creates a core-only model session', () {
    final session = createOrtSession('test/models/identity.onnx');
    expect(session.sessionPtr.value, isNot(nullptr));
    releaseOrtSessionObjects(session);
    // Explicit release is safe alongside the NativeFinalizer fallback.
    releaseOrtSessionObjects(session);
  });

  test('failed sessions consume statuses and leave ORT reusable', () {
    for (var iteration = 0; iteration < 32; iteration++) {
      expect(
        () => createOrtSession('test/models/does-not-exist-$iteration.onnx'),
        throwsException,
      );
    }
    final session = createOrtSession('test/models/identity.onnx');
    expect(session.sessionPtr.value, isNot(nullptr));
    releaseOrtSessionObjects(session);
  });

  test('bundled Extensions registers Whisper BpeDecoder', () {
    final session = createOrtSession(
      'test/models/bpe_decoder.onnx',
      includeOnnxExtensionsOps: true,
    );
    expect(session.sessionPtr.value, isNot(nullptr));
    releaseOrtSessionObjects(session);
  });
}
