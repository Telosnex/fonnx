# Pinned production inputs

`prebuilt.json` is the native and runtime-download manifest. The hook uses
`package:native_prebuilt` to select the release, check the source key and file
hashes, and publish three bundled libraries. The session finalizer is prebuilt
alongside Extensions, so consumer builds need no C compiler.

`upstream_ort.json` pins the upstream ORT URLs, archive hashes, exact archive
entries, and extracted library hashes. Source builds use these same inputs.
`tool/release_native.dart` preserves the Microsoft/Maven URLs. It uploads
Extensions, the finalizer, and unchanged copies of the two dynamic iOS ORT
files. The source build uses the existing pinned iOS base. The release workflow runs the hook for all ten supported targets.

`manifest.json` keeps the source pins, Web assets, model publication inputs, and
runtime constraints. Runtime models have their own immutable release and the
`runtimeFiles` section in `prebuilt.json`. The generated Dart catalog is in
`lib/src/native_prebuilt.g.dart`.

## Source profile 2

- ONNX Runtime 1.27.0:
  `8f0278c77bf44b0cc83c098c6c722b92a36ac4b5`
- ONNX Runtime Extensions:
  `fe4e13f46b19fb490c90b09fe280277308bd5bb7`
- Selected Extensions inventory: only `ai.onnx.contrib:BpeDecoder`
- ONNX Runtime Web 1.27.0 npm archive:
  `b59c9819434a7519f334f77e8d4bf22b69808d531a57724cabc4bb2c0704c835`
- Package-owned finalizer ABI: 1
- Package-owned Web Worker protocol ABI: 1

The complete intentional native matrix is Android armv7/arm64/x64, iOS arm64
device/simulator, Linux arm64/x64, macOS arm64, and Windows arm64/x64. Every
target has both an ORT and selected-op Extensions record. Unsupported tuples
fail during the build hook rather than falling back to an unpinned system
runtime.

The Linux Extensions producer uses Ubuntu 22.04. Its runtime baseline is glibc
2.35 and the Ubuntu 22.04 libstdc++. Profile 2 replaces the old Ubuntu 24.04
producer, whose Extensions files needed glibc 2.38 and `GLIBCXX_3.4.32`.
Windows requires the Microsoft Visual C++ 2015–2022 runtime.

Apple requirements stay at iOS 15.1 and macOS 14. The manifest stores the iOS
major version 15 because the shared schema uses integer versions. Flutter's
hook request is fixed at 13. `hook/apple_compatibility.dart` uses FONNX's declared
floor only for release selection, not for the source-build input. The README
contains the required iOS deployment target and framework packaging fix.

## Web runtime

The published `lib/web`, example, and deployed demo use the same local ORT Web
1.27 runtime. Workers
never import executable CDN code. ORT 1.27's single SIMD/thread-capable Wasm
build replaces the former mixed 1.17/1.19 worker imports and five 1.17-era Wasm
files. The manifest hashes all 19 canonical example assets, all 19 published
copies, and 16 deployed runtime/service-worker assets. The verifier also proves
that each model Worker imports `./ort.min.mjs`.

## Model inventory

The manifest records SHA-256 and byte length for 18 example and
conformance ONNX files. Verification rejects Git LFS pointer text explicitly,
which turns an otherwise confusing ORT `Invalid protobuf` error into a
supply-chain failure before tests run.

## Verification

```bash
dart run tool/verify_artifacts.dart
# Also re-download and independently hash every unique native archive:
dart run tool/verify_artifacts.dart --downloads
node tool/test_web_runtime.mjs
tool/test_macos_artifacts.sh
tool/test_ios_simulator_artifacts.sh
FONNX_ANDROID_AVD=Medium_Phone_API_36.0 tool/test_android_artifacts.sh
tool/test_linux_artifact_docker.sh linux-arm64
tool/test_linux_artifact_docker.sh linux-x64
tool/test_windows_artifact_wine.sh
```

The normal build hook checks both the archive hash and each extracted file
hash. `dart run native_prebuilt:check` checks the native and model release URLs.
Use `--download` to independently download and hash every file.
Licenses for bundled Microsoft runtime code are in the package `LICENSE`,
in the Flutter multi-license format.
