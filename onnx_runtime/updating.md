# Updating ONNX Runtime and Extensions

FONNX distributes native libraries with `hook/build.dart`. No ONNX binaries are
tracked in Git and no CocoaPods, Gradle dependency, or Flutter plugin wrapper is
part of the runtime path.

## Pinned components

- ONNX Runtime: `1.27.0` (`_ortVersion` in `hook/build.dart`).
- ONNX Runtime Extensions:
  `fe4e13f46b19fb490c90b09fe280277308bd5bb7`.
- Extensions selected-op inventory: `ai.onnx.contrib:BpeDecoder`, used only by
  FONNX's end-to-end Whisper graph.

## Updating ONNX Runtime

1. Check the upstream GitHub release and Maven Central. Pin the newest version
   available for **every** target. Maven lag is why the current common pin is
   1.27.0 even though a 1.27.1 GitHub release exists.
2. Update every ORT URL/digest in `hook/build.dart`. Digests for GitHub release
   assets are available from the GitHub release API. Compute and independently
   verify the Maven AAR's SHA-256.
3. Extract the release SDK headers into `onnx_runtime/headers`.
4. Regenerate the C ABI bindings:

   ```sh
   dart run ffigen --config onnx_runtime/ffigen_config.yaml
   dart format lib/onnx/ort_ffi_bindings.dart
   ```

   The generator intentionally enters through `onnxruntime_c_api.h`, not a
   glob of every SDK header. Provider headers contain C++ declarations that
   are not valid Dart FFI input.
5. Update `ORT_VERSION` in both producer workflows and build scripts.
6. Run the full Apple producer when ORT changes. Its fallback path invokes
   Microsoft's first-party `build_apple_framework.py --build_dynamic_framework`
   for arm64 iPhone and arm64 simulator. Publish
   that verified archive as the immutable Apple ORT base. Subsequent
   Extensions-only recipe changes set `ORT_PREBUILT_ARCHIVE_URL` and its
   SHA-256: the producer extracts only the unchanged ORT slices and rebuilds
   Extensions, avoiding another long ORT compile. Microsoft publishes only
   static iOS artifacts; FONNX's base fills that dynamic publishing gap.
7. Publish new producer outputs under a **new immutable prerelease tag**, then
   pin their downloaded SHA-256 values in `hook/build.dart`. Never use
   `gh release upload --clobber` on an asset referenced by a checked-in hash:
   old commits must remain buildable.

## Updating ONNX Runtime Extensions

1. Inspect every shipped model and enumerate non-core `(domain, op_type)`
   pairs. Do not infer dependencies from call-site flags. At the current pin,
   Magika and Pyannote use core ORT only; Whisper contains one
   `ai.onnx.contrib:BpeDecoder` node.
2. Update `ORTX_COMMIT` in:
   - `.github/workflows/build-ios-native-assets.yml`;
   - `.github/workflows/build-extensions-native-assets.yml`;
   - `tool/apple/build_ios_native_assets.sh`;
   - `tool/extensions/build_selected_extensions.sh`.
3. Update the generated `cmake/_selectedoplist.cmake` content in both scripts
   if the model inventory changed. Upstream's GPT-2 selected feature is broader
   than `BpeDecoder`; `tool/extensions/bpe_decoder_only.patch` narrows both the
   compiled source list and registered factory. Update that pinned-source patch
   as needed, and keep its `git apply --check` producer gate.
4. Run the Extensions matrix. It produces selected-op dynamic libraries for
   Android armv7/arm64/x64, Linux x64/aarch64, macOS arm64, and Windows
   x64/arm64. The Apple producer creates iOS device/simulator output.
5. Verify each sidecar digest after downloading the workflow artifacts; publish
   under the new prerelease; copy the final URLs and digests into the hook.

## Required verification

```sh
flutter analyze
flutter test test/ort_native_asset_test.dart
(cd example && flutter build apk --debug)
(cd example && flutter build ios --simulator)
```

`ort_native_asset_test.dart` checks all three important contracts:
`OrtGetApiBase`, core-model session creation, and Extensions registration by
creating a minimal graph containing `ai.onnx.contrib:BpeDecoder`.

Also run hydrated-model goldens with `flutter test --concurrency=1`. The suite
contains process-RSS smoke tests, so parallel test-file execution contaminates
their measurements with other concurrently loaded models. This checkout may
contain raw Git LFS pointer files rather than model bytes; `Invalid protobuf`
against a ~130-byte `.onnx` is an LFS checkout failure, not an ORT regression.
Re-baseline numerical goldens only after recording and reviewing the complete
before/after score set; ORT graph-optimizer upgrades can legitimately shift
cosine scores while preserving model ranking.

Audit outputs:

- every native target includes exactly one ORT and one Extensions code asset;
- `grep -R MethodChannel lib/` returns nothing;
- no `.so`, `.dylib`, or `.dll` is tracked by Git;
- iOS Runner and Podfile deployment targets are at least the upstream ORT
  requirement (15.1 for ORT 1.27.0);
- after a device Release build, the app and generated native-asset framework
  `MinimumOSVersion` values are not lower than any embedded Mach-O `minos`;
  Flutter 3.44.2 generates native-asset wrapper plists with its iOS 13
  baseline rather than a higher Runner target (see flutter/flutter#148044 and
  the open deployment-version tracking issue flutter/flutter#145104), so the
  post-`Thin Binary` correction/re-signing phase is required for ORT 1.27 to
  avoid App Store Connect `ITMS-90208`;
- macOS deployment target is at least 14.0 and Release builds request arm64
  only; Intel Apple targets are intentionally unsupported.
