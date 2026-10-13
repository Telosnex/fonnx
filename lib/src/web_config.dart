/// Browser-only configuration of the FONNX web runtime.
abstract final class FonnxWeb {
  /// The directory of the FONNX web runtime files: the init modules, the
  /// Workers and ONNX Runtime Web.
  ///
  /// In a Flutter web build, the fonnx build hook installs them in
  /// `web/native_prebuilt/fonnx/` of the app, which is the default
  /// (native_prebuilt ADR 002). Other embedders serve the files of
  /// `native_artifacts/web.json` same-origin and set this URI. A relative URI
  /// resolves against the document base URI. Set it before the first model
  /// call.
  static Uri runtimeUri = Uri.parse('native_prebuilt/fonnx/');
}
