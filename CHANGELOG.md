## 0.0.1

* Use `native_prebuilt` for the native hook, shared verified cache, source-key
  selection, and build modes. Release CI builds selected-op Extensions and the
  session finalizer through the hook for all ten targets. Consumer builds no
  longer compile the finalizer. Upstream ONNX Runtime URLs stay unchanged.
* Publish the 16 example ONNX models as verified runtime downloads. The
  `runtime_models.dart` API exposes their pinned catalog and download helper.
* Build Linux Extensions on Ubuntu 22.04 (glibc 2.35) instead of Ubuntu 24.04.
* Make `native_artifacts/manifest.json` the canonical source for all ten native
  target pairs, ORT/Extensions/Web source pins, Web assets, and model fixtures.
* Align native and Web on ONNX Runtime 1.27.0, remove mixed 1.17/1.19 workers,
  vendor the Web runtime locally, and remove executable CDN dependencies.
* Consume every owned `OrtStatus` exactly once and clean partial session state
  on all model/session construction failures.
* Add an explicit package finalizer ABI and an 8,192-case ownership corpus
  under AddressSanitizer and UndefinedBehaviorSanitizer.
* Snapshot mutable audio, token, byte, state, and keyword inputs at API entry;
  validate hostile keyword/path/search configuration in release builds.
* Add 21 deterministic frontend recipes, exact model/runtime verification,
  real local Web identity and Magika Worker inference, a fatal-safe versioned
  Worker RPC, and one authoritative serialized gate.
* Runtime-test exact archives on macOS, iOS Simulator, Android API 36, Linux
  arm64/x64, and Windows/Wine; record the existing Linux Extensions floor as
  glibc 2.38/`GLIBCXX_3.4.32` instead of implying glibc 2.31 compatibility.
