#!/usr/bin/env bash
# Cross-platform producer for fonnx's selected-op ONNX Runtime Extensions asset.
# Runs in release CI, never from hook/build.dart.

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly FONNX_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly TARGET_OS="${TARGET_OS:?Set TARGET_OS: android, linux, macos, or windows}"
readonly TARGET_ARCH="${TARGET_ARCH:?Set TARGET_ARCH for TARGET_OS}"
readonly ORT_EXTENSIONS_ROOT="${ORT_EXTENSIONS_ROOT:?Set ORT_EXTENSIONS_ROOT}"
readonly ORTX_COMMIT="${ORTX_COMMIT:-fe4e13f46b19fb490c90b09fe280277308bd5bb7}"
readonly ORT_VERSION="${ORT_VERSION:-1.27.0}"
readonly BUILD_ROOT="${BUILD_ROOT:-${RUNNER_TEMP:-/tmp}/fonnx-ortextensions-${TARGET_OS}-${TARGET_ARCH}}"
readonly OUTPUT_DIR="${OUTPUT_DIR:-$FONNX_ROOT/dist}"
readonly ORT_HEADERS_PACKAGE="$BUILD_ROOT/ort-package"
readonly SELECTED_OPS_FILE="$ORT_EXTENSIONS_ROOT/cmake/_selectedoplist.cmake"
readonly ASSET_BASENAME="fonnx-ortextensions-${ORTX_COMMIT:0:8}-${TARGET_OS}-${TARGET_ARCH}"

rm -rf "$BUILD_ROOT"
mkdir -p "$BUILD_ROOT" "$OUTPUT_DIR" "$ORT_HEADERS_PACKAGE/include"
cp -R "$FONNX_ROOT/onnx_runtime/headers/." "$ORT_HEADERS_PACKAGE/include/"

cleanup() {
  rm -f "$SELECTED_OPS_FILE"
}
trap cleanup EXIT
cat > "$SELECTED_OPS_FILE" <<'CMAKE'
# Generated from fonnx's model inventory: Whisper has exactly this custom op.
set(OCOS_ENABLE_GPT2_TOKENIZER ON CACHE INTERNAL "")
CMAKE

cmake_args=(
  -S "$ORT_EXTENSIONS_ROOT"
  -B "$BUILD_ROOT/build"
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5
  -DONNXRUNTIME_PKG_DIR="$ORT_HEADERS_PACKAGE"
  -DOCOS_ONNXRUNTIME_VERSION="$ORT_VERSION"
  -DOCOS_ENABLE_SELECTED_OPLIST=ON
  -DOCOS_ENABLE_CTEST=OFF
  -DOCOS_BUILD_SHARED_LIB=ON
)

case "$TARGET_OS-$TARGET_ARCH" in
  linux-x64)
    cmake_args+=(
      -DCMAKE_BUILD_TYPE=Release
      -DCMAKE_SYSTEM_PROCESSOR=x86_64
    )
    ;;
  linux-arm64)
    cmake_args+=(
      -DCMAKE_BUILD_TYPE=Release
      -DCMAKE_SYSTEM_NAME=Linux
      -DCMAKE_SYSTEM_PROCESSOR=aarch64
      -DCMAKE_C_COMPILER=aarch64-linux-gnu-gcc
      -DCMAKE_CXX_COMPILER=aarch64-linux-gnu-g++
    )
    ;;
  macos-arm64)
    cmake_args+=(
      -DCMAKE_BUILD_TYPE=Release
      -DCMAKE_OSX_ARCHITECTURES=arm64
      -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0
    )
    ;;
  windows-x64)
    cmake_args+=(-A x64)
    ;;
  windows-arm64)
    cmake_args+=(-A ARM64)
    ;;
  android-arm)
    : "${ANDROID_NDK_HOME:?Set ANDROID_NDK_HOME for Android builds}"
    cmake_args+=(
      -DCMAKE_BUILD_TYPE=Release
      -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake"
      -DANDROID_ABI=armeabi-v7a
      -DANDROID_PLATFORM=android-21
    )
    ;;
  android-arm64)
    : "${ANDROID_NDK_HOME:?Set ANDROID_NDK_HOME for Android builds}"
    cmake_args+=(
      -DCMAKE_BUILD_TYPE=Release
      -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake"
      -DANDROID_ABI=arm64-v8a
      -DANDROID_PLATFORM=android-21
    )
    ;;
  android-x64)
    : "${ANDROID_NDK_HOME:?Set ANDROID_NDK_HOME for Android builds}"
    cmake_args+=(
      -DCMAKE_BUILD_TYPE=Release
      -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake"
      -DANDROID_ABI=x86_64
      -DANDROID_PLATFORM=android-21
    )
    ;;
  *)
    echo "Unsupported target: $TARGET_OS-$TARGET_ARCH" >&2
    exit 64
    ;;
esac

cmake "${cmake_args[@]}"
if [[ "$TARGET_OS" == windows ]]; then
  cmake --build "$BUILD_ROOT/build" \
    --config Release --target extensions_shared --parallel 8
else
  cmake --build "$BUILD_ROOT/build" \
    --target extensions_shared --parallel 8
fi

case "$TARGET_OS" in
  windows)
    library="$(find "$BUILD_ROOT/build" -type f -iname 'ortextensions.dll' | head -1)"
    output_name=ortextensions.dll
    ;;
  macos)
    library="$(find "$BUILD_ROOT/build" -type f -name 'libortextensions.*.dylib' | head -1)"
    output_name=libortextensions.dylib
    ;;
  android|linux)
    library="$(find "$BUILD_ROOT/build" -type f -name 'libortextensions.so*' | head -1)"
    output_name=libortextensions.so
    ;;
esac

test -n "${library:-}"
test -s "$library"
# A full binary strings scan is intentionally portable across native and
# cross-compiled outputs; platform-specific nm/dumpbin checks run in the hook's
# consumer smoke tests too.
if ! strings "$library" | grep 'RegisterCustomOps' >/dev/null; then
  echo "RegisterCustomOps is not exported by $library" >&2
  exit 1
fi

readonly STAGING="$BUILD_ROOT/staging"
mkdir -p "$STAGING"
cp "$library" "$STAGING/$output_name"
printf '%s\n' \
  "ORT_VERSION=$ORT_VERSION" \
  "ORTX_COMMIT=$(git -C "$ORT_EXTENSIONS_ROOT" rev-parse HEAD)" \
  "TARGET=$TARGET_OS-$TARGET_ARCH" \
  "SELECTED_EXTENSION_OPS=ai.onnx.contrib:BpeDecoder" \
  > "$STAGING/provenance.txt"

readonly ASSET_PATH="$OUTPUT_DIR/$ASSET_BASENAME.zip"
rm -f "$ASSET_PATH" "$ASSET_PATH.sha256"
(
  cd "$STAGING"
  cmake -E tar cf "$ASSET_PATH" --format=zip "$output_name" provenance.txt
)
cmake -E sha256sum "$ASSET_PATH" | tee "$ASSET_PATH.sha256"
printf 'Built %s\n' "$ASSET_PATH"
