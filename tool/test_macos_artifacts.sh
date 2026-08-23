#!/usr/bin/env bash
# Execute core and selected-op sessions against the exact manifest-selected
# macOS arm64 archives.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
[[ "$(uname -s)-$(uname -m)" == Darwin-arm64 ]] || {
  echo 'The intentional macOS matrix is Apple Silicon only.' >&2
  exit 1
}
build="$root/build/runtime/macos-arm64"
dart run "$root/tool/materialize_runtime_artifacts.dart" macos-arm64 "$build"
xcrun clang -std=c11 -O2 -Wall -Wextra -Werror \
  -I"$root/onnx_runtime/headers" "$root/tool/support/ort_runtime_smoke.c" \
  -L"$build" -lortextensions -lonnxruntime \
  -Wl,-rpath,@executable_path -o "$build/ort_runtime_smoke"
cp "$root/test/models/identity.onnx" "$root/test/models/bpe_decoder.onnx" "$build/"
"$build/ort_runtime_smoke" "$build/identity.onnx" "$build/bpe_decoder.onnx"
echo 'PASS: exact macos-arm64 manifest artifacts'
