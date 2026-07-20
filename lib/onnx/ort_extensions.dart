import 'dart:ffi';

import 'package:fonnx/onnx/ort_ffi_bindings.dart';

typedef _RegisterOrtExtensionsNative =
    Pointer<OrtStatus> Function(
      Pointer<OrtSessionOptions>,
      Pointer<OrtApiBase>,
    );

typedef _RegisterOrtExtensionsDart =
    Pointer<OrtStatus> Function(
      Pointer<OrtSessionOptions>,
      Pointer<OrtApiBase>,
    );

/// Registers the custom operators exported by ONNX Runtime Extensions.
///
/// The build hook maps this Dart library URI to `libortextensions`. Calling the
/// export directly is native-assets-aware and avoids passing a platform- and
/// bundle-specific filesystem path through ORT's `RegisterCustomOpsLibrary`.
@Native<_RegisterOrtExtensionsNative>(symbol: 'RegisterCustomOps')
external Pointer<OrtStatus> _registerBundledOrtExtensions(
  Pointer<OrtSessionOptions> options,
  Pointer<OrtApiBase> apiBase,
);

Pointer<OrtStatus> registerOrtExtensions({
  required Pointer<OrtSessionOptions> options,
  required Pointer<OrtApiBase> apiBase,
  String? libraryPathOverride,
}) {
  if (libraryPathOverride == null) {
    return _registerBundledOrtExtensions(options, apiBase);
  }
  return DynamicLibrary.open(
    libraryPathOverride,
  ).lookupFunction<_RegisterOrtExtensionsNative, _RegisterOrtExtensionsDart>(
    'RegisterCustomOps',
  )(options, apiBase);
}
