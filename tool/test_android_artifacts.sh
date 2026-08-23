#!/usr/bin/env bash
# Execute core and selected-op sessions against exact Android artifacts on a
# connected device/emulator. Set FONNX_ANDROID_AVD to start an AVD.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
adb="$sdk/platform-tools/adb"
emulator="$sdk/emulator/emulator"
ndk="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-$sdk/ndk/28.2.13676358}}"
[[ -x "$adb" && -d "$ndk" ]] || { echo 'Android SDK/NDK missing.' >&2; exit 1; }
started=false; emulator_pid=
cleanup() {
  "$adb" shell 'rm -rf /data/local/tmp/fonnx_runtime_smoke' >/dev/null 2>&1 || true
  if [[ "$started" == true && "${FONNX_KEEP_ANDROID_RUNNING:-0}" != 1 ]]; then
    "$adb" emu kill >/dev/null 2>&1 || true
    [[ -z "$emulator_pid" ]] || kill "$emulator_pid" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT
if ! "$adb" get-state >/dev/null 2>&1; then
  avd="${FONNX_ANDROID_AVD:-}"
  [[ -n "$avd" ]] || { echo 'No device; set FONNX_ANDROID_AVD.' >&2; exit 1; }
  "$emulator" -avd "$avd" -no-window -no-audio -no-boot-anim \
    -gpu swiftshader_indirect >"$root/build/fonnx-android-emulator.log" 2>&1 &
  emulator_pid=$!; started=true; "$adb" wait-for-device
fi
for _ in $(seq 1 180); do
  [[ "$("$adb" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == 1 ]] && break
  sleep 1
done
abi="$("$adb" shell getprop ro.product.cpu.abi | tr -d '\r')"
case "$abi" in
  arm64-v8a) target=android-arm64; triple=aarch64-linux-android; compiler=aarch64-linux-android24-clang ;;
  armeabi-v7a) target=android-arm; triple=arm-linux-androideabi; compiler=armv7a-linux-androideabi24-clang ;;
  x86_64) target=android-x64; triple=x86_64-linux-android; compiler=x86_64-linux-android24-clang ;;
  *) echo "Unsupported Android ABI: $abi" >&2; exit 1 ;;
esac
case "$(uname -s)" in Darwin) host=darwin-x86_64 ;; Linux) host=linux-x86_64 ;; *) exit 1 ;; esac
cc="$ndk/toolchains/llvm/prebuilt/$host/bin/$compiler"
build="$root/build/runtime/$target"
dart run "$root/tool/materialize_runtime_artifacts.dart" "$target" "$build"
"$cc" -std=c11 -O2 -Wall -Wextra -Werror \
  -I"$root/onnx_runtime/headers" "$root/tool/support/ort_runtime_smoke.c" \
  -L"$build" -lortextensions -lonnxruntime \
  -Wl,--allow-shlib-undefined -Wl,-rpath,'$ORIGIN' \
  -o "$build/ort_runtime_smoke"
libcxx="$ndk/toolchains/llvm/prebuilt/$host/sysroot/usr/lib/$triple/libc++_shared.so"
[[ -f "$libcxx" ]] || { echo "Missing $libcxx" >&2; exit 1; }
cp "$root/test/models/identity.onnx" "$root/test/models/bpe_decoder.onnx" "$build/"
remote=/data/local/tmp/fonnx_runtime_smoke
"$adb" shell "rm -rf $remote && mkdir $remote"
"$adb" push "$build/ort_runtime_smoke" "$build/libonnxruntime.so" \
  "$build/libortextensions.so" "$libcxx" "$build/identity.onnx" \
  "$build/bpe_decoder.onnx" "$remote/" >/dev/null
"$adb" shell "chmod 755 $remote/ort_runtime_smoke && cd $remote && LD_LIBRARY_PATH=. ./ort_runtime_smoke identity.onnx bpe_decoder.onnx"
echo "PASS: exact $target manifest artifacts on Android API $("$adb" shell getprop ro.build.version.sdk | tr -d '\r')"
