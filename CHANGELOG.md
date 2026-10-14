## 0.0.1

* The model files moved from Git and the GitHub runtime release to Hugging
  Face `telosnex/fonnx`. `nativePrebuiltRuntimeFiles` pins each file by
  Hugging Face commit and SHA-256, and now also has the four NemoAsr files.
  `tool/fetch_hf_models.dart` downloads the models for the tests and the
  example app. The old GitHub release stays for earlier fonnx commits.
* Add `NemoAsr`: speech-to-text with NVIDIA's multilingual FastConformer CTC
  (10 languages, 132 MB) or Parakeet TDT 0.6B v3 (25 European languages,
  670 MB). Both are the int8 exports of sherpa-onnx, downloaded from Hugging
  Face. Native and web. Log-mel features, greedy CTC and TDT decoding, and
  token decoding are in shared Dart. On FLEURS, the CTC model is about as
  accurate as Whisper small and 3x faster than Whisper tiny; v3 is more
  accurate than Whisper small outside English.
* Whisper runs the split fp32 export of `onnx-community/whisper-tiny`
  (encoder, and merged decoder with a key/value cache) on stock ORT, native
  and web. Log-mel features, a 2-beam search with Whisper's token
  suppression, and token decoding are in shared Dart. ORT Extensions are no
  longer needed for Whisper. `Whisper.load` takes a `WhisperBundle`;
  `Whisper.removeTimestamps` is removed because timestamp tokens are
  suppressed.
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
