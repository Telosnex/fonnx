# Updating ONNX Runtime

FONNX ships ONNX Runtime (ORT) through `hook/build.dart`. No ORT binaries are
tracked in Git. The `Upstream watch` workflow alerts when a newer minor ORT release is on
GitHub, Maven and npm (`.github/ort_watch.dart`). It also alerts when a
release has waited more than 14 days for Maven or npm.

The 1.27.0 → 1.31.1 update ([#34](https://github.com/Telosnex/fonnx/pull/34))
is a worked example of everything below.

## Where ORT is pinned

| What | File |
|---|---|
| Native archives: URL, archive hash, library hash, for every target | `native_artifacts/upstream_ort.json` |
| The same archives as kiln sources | `native_artifacts/sources.json` |
| Version and ORT commit | `native_artifacts/manifest.json` (`sources.onnxRuntime`) |
| ORT Web npm package and its files | `web_build/onnxruntime_web.json`, and `sources.onnxRuntimeWeb` in `manifest.json` |
| Deployed demo's ORT Web files (size and hash) | `docs/`, and `deployedWebAssets` in `manifest.json` |
| C headers and Dart bindings | `onnx_runtime/headers/`, `lib/onnx/ort_ffi_bindings.dart` |
| iOS build default | `ORT_VERSION` in `tool/apple/build_ios_native_assets.sh` |

**The version is also hard-coded in checks.** Every one must change, or the
check fails. Find them with
`git grep -nE "1\.27\.|'1\.27" -- ':!*.wasm' ':!*.mjs' ':!lib/onnx/ort_ffi_bindings.dart'`
(with the old version). In 1.31.1 they were:

- `hook_src/upstream_ort.dart` (`json['version'] != …`)
- `tool/verify_artifacts.dart` (`_expectedSources`: versions, commit, npm hash)
- `tool/test_web_runtime.mjs` (`ort.env.versions`)
- `tool/support/ort_runtime_smoke.c` (`GetVersionString` prefix)
- `test/kiln_release_test.dart`

Notes in `test/data/` that name the ORT version that produced a golden are
history; leave them.

## Steps

1. **Check the version exists everywhere.** GitHub release (Linux, macOS,
   Windows archives), Maven Central (`onnxruntime-android`, which can lag), and
   npm (`onnxruntime-web`). Take the newest version on all three.
2. **Download and verify.**
   - GitHub archives: compare with the `digest` the release API returns.
   - Maven publishes no SHA-256 for the AAR: check its `.sha1` and `.md5`.
   - npm: compare with the package's `dist.integrity` (SHA-512).
   - Hash both the archive and the library inside it; `upstream_ort.json`
     pins both.
   - Check the macOS library's `minos` (`otool -l … | grep -A3
     LC_BUILD_VERSION`) is still at most 14.0.
3. **Update the pins** in the table above, and the hard-coded checks.
4. **Headers and bindings.** Copy the macOS archive's `include/` into
   `onnx_runtime/headers/` (it includes `webgpu_provider_factory.h`), then:

   ```sh
   dart run ffigen --config onnx_runtime/ffigen_config.yaml
   dart format lib/onnx/ort_ffi_bindings.dart
   ```

   `ORT_API_VERSION` in the bindings becomes the new version's API. ORT only
   appends to `OrtApi`; check the existing entries are unchanged. Don't run
   `dart format lib`: it reformats the generated `lib/src/kiln.g.dart`.
5. **Web.** Update `web_build/onnxruntime_web.json`, then install the files and
   copy the three ORT files into `docs/`, updating their entries in
   `deployedWebAssets`:

   ```sh
   dart run tool/kiln/build_web.dart --out /tmp/fonnx_web
   dart run kiln:web install-dev --from /tmp/fonnx_web
   cp lib/web/{ort.min.mjs,ort-wasm-simd-threaded.mjs,ort-wasm-simd-threaded.wasm} docs/
   ```

6. **iOS.** Microsoft publishes only a static iOS ORT, and Flutter native
   assets need a dynamic library, so FONNX builds its own. With a checkout of
   the release tag (check its commit matches `manifest.json`):

   ```sh
   ORT_VERSION=… ORT_COMMIT=… ORT_ROOT=…/onnxruntime \
     BUILD_ROOT=…/out OUTPUT_DIR=…/dist \
     caffeinate -i tool/apple/build_ios_native_assets.sh
   ```

   This takes about an hour on an M4 Max; allow 20 GB or more of disk. Check
   both libraries export `OrtGetApiBase` and report the new version, then
   publish the zip, its `.sha256` and `provenance.txt` as a **new** prerelease,
   `native-assets-ort-<version>`, and pin it in `upstream_ort.json` and
   `sources.json`. Never replace a file that a checked-in hash refers to.
7. **Test locally** (see below), and benchmark (see below).
8. **Kiln release.** Native changes change the source key, so CI fails
   (`kiln:check`, web, `verify_artifacts`, Android) until a release matches:
   push the branch to `kiln-release`, then fast-forward the branch onto the
   `kiln-manifest/<tag>` commit the release pushes. Every later change to
   native sources (including `tool/support/*.c`) needs another release.
   Everything the package publishes counts, so check with `dart run
   kiln:check` before pushing. `native_artifacts/source_excludes.txt` lists
   what doesn't count; keep it in step with `.pubignore`, or the published
   package's key differs from the release's.
9. **PR and CI.** Integration does not run on pull requests: start it on the
   branch with `gh workflow run integration.yml --ref <branch>`. Merge with
   rebase, not squash, so the manifest commits stay as they are.

## Testing

Record a baseline on the old version first, so a failure is clearly the
update's.

```sh
dart run tool/fetch_hf_models.dart
dart test --concurrency=1 -x perf          # memory tests need concurrency 1
tool/test_native_sanitizers.sh
node tool/test_web_runtime.mjs
dart test test/web_runtime_test.dart -p chrome -c dart2js,dart2wasm
(cd example && flutter test integration_test/ios_all.dart -d <simulator>)
```

After the kiln release, also `dart run kiln:check`,
`dart run tool/verify_artifacts.dart` and `tool/test_macos_artifacts.sh`;
before it, these fail by design.

Check the tests loaded the new ORT: the hook's log names the archive it
fetched, and the app built for the simulator contains the version string.

## Benchmarking

`test/bench/ort_bench.dart` times each model on fixed inputs. Alternate versions so
machine noise shows as spread, not as a difference, with 8 rounds each:

```sh
for r in 1 2 3 4 5 6 7 8; do
  for b in main <branch>; do
    git switch -q $b
    dart run test/bench/ort_bench.dart 2>/dev/null | grep '^{' >> /tmp/bench_$b.jsonl
  done
done
```

Compare the medians per model, and test the difference (e.g. Mann-Whitney).
#34's description has the table from 1.27.0 → 1.31.1.

## Workarounds tied to an ORT version

Search for the old version in comments: a workaround may name the version
that fixes it. In 1.31.1 the keyword spotter's `mlas.disable_kleidiai`
workaround for microsoft/onnxruntime#28571 was removed; its tests detect and
transcribe real speech, so they catch the bug. The iOS build is configured
with `--no_kleidiai`.

## Apple deployment targets

- iOS Runner and Podfile deployment targets are at least the upstream ORT
  requirement (15.1 for ORT 1.31.1).
- After a device Release build, the app and native-asset framework
  `MinimumOSVersion` values are not lower than any embedded Mach-O `minos`.
  Flutter generates native-asset framework plists with its own iOS baseline
  (flutter/flutter#148044, #145104), so the Runner's "Align FONNX Framework
  Minimum OS" phase after `Thin Binary` is required to avoid App Store
  Connect `ITMS-90208`.
- macOS deployment target is at least 14.0 and Release builds are arm64 only;
  Intel Apple targets are unsupported.
