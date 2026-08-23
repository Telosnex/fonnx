# Pinned production inputs

`manifest.json` is the canonical supply-chain record used directly by
`hook/build.dart`. FONNX does not commit native ORT libraries: the hook selects
one immutable archive record for the target tuple, downloads it into a
content-addressed cache, verifies SHA-256, extracts exactly one named library,
and bundles it as a code asset.

## Source profile 1

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

The current Linux Extensions producer is Ubuntu 24.04 and the binary floor is
therefore glibc 2.38 plus `GLIBCXX_3.4.32`. Exact-artifact tests intentionally
proved that it does not run on glibc 2.31. The producer and manifest now lock
that fact rather than advertising accidental compatibility. Lowering the floor
requires rebuilding/publishing a new immutable Extensions profile with an
older sysroot. Windows requires the Microsoft Visual C++ 2015–2022 runtime.

## Web runtime

The published `lib/web`, example, and deployed demo use the same local ORT Web
1.27 runtime. Workers
never import executable CDN code. ORT 1.27's single SIMD/thread-capable Wasm
build replaces the former mixed 1.17/1.19 worker imports and five 1.17-era Wasm
files. The manifest hashes all 19 canonical example assets, all 19 published
copies, and 16 deployed runtime/service-worker assets. The verifier also proves
that each model Worker imports `./ort.min.mjs`.

## Model inventory

The manifest records SHA-256 and byte length for 14 supported/example and
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

The normal build hook independently verifies the selected downloaded archive.
Licenses for bundled Microsoft runtime code are under `licenses/`.
