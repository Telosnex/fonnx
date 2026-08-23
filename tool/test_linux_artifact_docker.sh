#!/usr/bin/env bash
# Runtime-test exact manifest-selected Linux artifacts in a clean matching-arch
# glibc container.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
target="${1:-}"
case "$target" in
  linux-x64)
    platform=linux/amd64
    image='ubuntu@sha256:1e0a86e57d247923571b75e0aaf48a1449cf8c543d51fb3e07a4a7d7bfa79316'
    ;;
  linux-arm64)
    platform=linux/arm64
    image='ubuntu@sha256:95fa486768020359141f1318720f43e7982ef926c792891d984aef9aaf05e7ea'
    ;;
  *) echo "Usage: $0 <linux-x64|linux-arm64>" >&2; exit 64 ;;
esac
build="$root/build/runtime/$target"
dart run "$root/tool/materialize_runtime_artifacts.dart" "$target" "$build"
cp "$root/test/models/identity.onnx" "$root/test/models/bpe_decoder.onnx" "$build/"

docker run --rm --platform "$platform" -v "$root:/workspace" -w /workspace \
  "$image" bash -lc '
    set -euo pipefail
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y --no-install-recommends gcc libc6-dev libstdc++6 >/dev/null
    target='"$target"'
    build="build/runtime/$target"
    gcc -std=c11 -O2 -Wall -Wextra -Werror -I onnx_runtime/headers \
      tool/support/ort_runtime_smoke.c -L "$build" \
      -lortextensions -lonnxruntime -Wl,-rpath,'"'"'$ORIGIN'"'"' \
      -o "$build/ort_runtime_smoke"
    "$build/ort_runtime_smoke" "$build/identity.onnx" "$build/bpe_decoder.onnx"
  '
echo "PASS: exact $target manifest artifacts in clean $platform container"
