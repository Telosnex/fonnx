#!/usr/bin/env bash
# Runtime-test exact manifest-selected Windows x64 artifacts under Wine.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
build="$root/build/runtime/windows-x64"
dart run "$root/tool/materialize_runtime_artifacts.dart" windows-x64 "$build"
cp "$root/test/models/identity.onnx" "$root/test/models/bpe_decoder.onnx" "$build/"
vc_redist="$build/vc_redist.x64.exe"
vc_redist_sha=cc0ff0eb1dc3f5188ae6300faef32bf5beeba4bdd6e8e445a9184072096b713b
if [[ ! -f "$vc_redist" ]] || \
    [[ "$(shasum -a 256 "$vc_redist" | awk '{print $1}')" != "$vc_redist_sha" ]]; then
  curl -fL --retry 3 https://aka.ms/vs/17/release/vc_redist.x64.exe \
    -o "$vc_redist"
fi
[[ "$(shasum -a 256 "$vc_redist" | awk '{print $1}')" == "$vc_redist_sha" ]] || {
  echo 'Pinned Microsoft Visual C++ runtime hash mismatch.' >&2; exit 1;
}
cat >"$build/onnxruntime.def" <<'DEF'
LIBRARY onnxruntime.dll
EXPORTS
  OrtGetApiBase
DEF
cat >"$build/ortextensions.def" <<'DEF'
LIBRARY ortextensions.dll
EXPORTS
  RegisterCustomOps
DEF

docker run --rm --platform linux/amd64 -v "$root:/workspace" -w /workspace \
  debian:bullseye-slim@sha256:cba95a21c96c1f5fc2470081829363eed57706634f7dc26e8c6712934303d57a \
  bash -lc '
    set -euo pipefail
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y --no-install-recommends \
      gcc-mingw-w64-x86-64-posix binutils-mingw-w64-x86-64 wine64 \
      cabextract >/dev/null
    build=build/runtime/windows-x64
    x86_64-w64-mingw32-dlltool -d "$build/onnxruntime.def" \
      -D onnxruntime.dll -l "$build/libonnxruntime.dll.a"
    x86_64-w64-mingw32-dlltool -d "$build/ortextensions.def" \
      -D ortextensions.dll -l "$build/libortextensions.dll.a"
    x86_64-w64-mingw32-gcc-posix -std=c11 -O2 -Wall -Wextra -Werror \
      -static -static-libgcc -I onnx_runtime/headers \
      tool/support/ort_runtime_smoke.c "$build/libortextensions.dll.a" \
      "$build/libonnxruntime.dll.a" -o "$build/ort_runtime_smoke.exe"
    rm -rf "$build/vc-runtime" && mkdir -p "$build/vc-runtime/payload"
    cabextract -q -d "$build/vc-runtime" "$build/vc_redist.x64.exe"
    cabextract -q -d "$build/vc-runtime/payload" "$build/vc-runtime/a12"
    for source in "$build"/vc-runtime/payload/*.dll_amd64; do
      name="$(basename "$source" _amd64)"
      cp "$source" "$build/$name"
    done
    cd "$build"
    export WINEDEBUG=-all WINEPREFIX=/tmp/fonnx-wine
    /usr/lib/wine/wine64 ./ort_runtime_smoke.exe identity.onnx bpe_decoder.onnx
  '
echo 'PASS: exact windows-x64 manifest artifacts under Wine'
