import 'dart:ffi';

import 'package:fonnx/onnx/ort_ffi_bindings.dart';

/// Registers the custom operators exported by ONNX Runtime Extensions.
///
/// The build hook maps this Dart library URI to `libortextensions`. Calling the
/// export directly is native-assets-aware and avoids passing a platform- and
/// bundle-specific filesystem path through ORT's `RegisterCustomOpsLibrary`.
@Native<
  Pointer<OrtStatus> Function(Pointer<OrtSessionOptions>, Pointer<OrtApiBase>)
>(symbol: 'RegisterCustomOps')
external Pointer<OrtStatus> registerOrtExtensions(
  Pointer<OrtSessionOptions> options,
  Pointer<OrtApiBase> apiBase,
);
