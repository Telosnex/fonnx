## 0.0.1

* Use `kiln`, the new name of `native_prebuilt`, from pub.dev.
  `nativePrebuiltRuntimeFiles` is now `prebuiltRuntimeFiles`, and the web
  files load from `kiln/fonnx/` (`FonnxWeb.runtimeUri`). The release
  workflow is `kiln_release.yml`, from `Telosnex/telosnex_ci_tools`.
* Remove ONNX Runtime Extensions. No model needs a custom operator, so the
  native assets are ONNX Runtime and the session finalizer, and the release
  builds no Extensions. `createOrtSession` no longer takes
  `includeOnnxExtensionsOps`, and `fonnxOrtExtensionsDylibPathOverride` is
  gone. On iOS, the Run Script phase aligns only `onnxruntime.framework`.
* Add `SenseVoice`: speech-to-text with Alibaba's SenseVoice Small (239 MB,
  int8 sherpa-onnx export): Mandarin, Cantonese, English, Japanese and
  Korean, with the language detected or set. Native and web. Kaldi filter
  bank features, greedy CTC and token decoding are in shared Dart. On FLEURS:
  5.5% CER Mandarin, 6.4% Japanese, 7.7% Korean, 7.0% WER English (Whisper
  Small: 9.8, 12.3, 8.9, 6.2). The NeMo log-mel features and SenseVoice share
  `lib/src/power_spectrum.dart`.
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
  selection, and build modes. Release CI builds the session finalizer through
  the hook for all ten targets. Consumer builds no
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
