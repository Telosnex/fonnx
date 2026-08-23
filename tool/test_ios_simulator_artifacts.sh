#!/usr/bin/env bash
# Execute core and selected-op sessions against the exact iOS Simulator archive.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
[[ "$(uname -s)-$(uname -m)" == Darwin-arm64 ]] || {
  echo 'Requires Apple Silicon macOS/Xcode.' >&2; exit 1;
}
target=ios-arm64-iphonesimulator
build="$root/build/runtime/$target"
dart run "$root/tool/materialize_runtime_artifacts.dart" "$target" "$build"
cp "$root/test/models/identity.onnx" "$root/test/models/bpe_decoder.onnx" "$build/"
sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
xcrun --sdk iphonesimulator clang -std=c11 -O2 -Wall -Wextra -Werror \
  -arch arm64 -mios-simulator-version-min=15.1 -isysroot "$sdk" \
  -I"$root/onnx_runtime/headers" "$root/tool/support/ort_runtime_smoke.c" \
  -L"$build" -lortextensions -lonnxruntime -Wl,-rpath,@executable_path \
  -o "$build/ort_runtime_smoke"
codesign -s - --force "$build/ort_runtime_smoke" \
  "$build/libonnxruntime.dylib" "$build/libortextensions.dylib" >/dev/null

read -r udid state < <(xcrun simctl list devices available -j | python3 -c '
import json,sys
c=[]
for runtime,devices in json.load(sys.stdin)["devices"].items():
  if "SimRuntime.iOS-" not in runtime: continue
  for d in devices:
    if d.get("isAvailable",True): c.append((d.get("state")=="Booted",runtime,d))
if not c: raise SystemExit("No available iOS Simulator")
c.sort(key=lambda x:(x[0],x[1]),reverse=True);d=c[0][2];print(d["udid"],d.get("state","Shutdown"))')
booted_here=false
cleanup() {
  if [[ "$booted_here" == true && "${FONNX_KEEP_SIMULATOR_BOOTED:-0}" != 1 ]]; then
    xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT
if [[ "$state" != Booted ]]; then xcrun simctl boot "$udid"; booted_here=true; fi
xcrun simctl bootstatus "$udid" -b
xcrun simctl spawn "$udid" "$build/ort_runtime_smoke" \
  "$build/identity.onnx" "$build/bpe_decoder.onnx"
echo "PASS: exact $target manifest artifacts on simulator $udid"
