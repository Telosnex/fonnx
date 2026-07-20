#!/usr/bin/env bash
# Build the two dynamic native assets required by fonnx on iOS.
#
# Required environment variables:
#   ORT_ROOT             onnxruntime checkout at ORT_VERSION
#   ORT_EXTENSIONS_ROOT  onnxruntime-extensions checkout at ORTX_COMMIT
#
# Optional:
#   OUTPUT_DIR           final artifact directory (default: ./dist)
#   BUILD_ROOT           disposable build root (default: $RUNNER_TEMP/fonnx-ios)
#   ORT_VERSION          default 1.27.0
#   ORTX_COMMIT          provenance label; default is the pinned commit below

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly FONNX_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly ORT_VERSION="${ORT_VERSION:-1.27.0}"
readonly ORTX_COMMIT="${ORTX_COMMIT:-fe4e13f46b19fb490c90b09fe280277308bd5bb7}"
readonly IOS_DEPLOYMENT_TARGET="15.1"
readonly BUILD_ROOT="${BUILD_ROOT:-${RUNNER_TEMP:-/tmp}/fonnx-ios-native-assets}"
readonly OUTPUT_DIR="${OUTPUT_DIR:-$FONNX_ROOT/dist}"
readonly ASSET_NAME="fonnx-ios-arm64-ort-${ORT_VERSION}-ortx-${ORTX_COMMIT:0:8}.zip"

: "${ORT_ROOT:?Set ORT_ROOT to an onnxruntime checkout at v$ORT_VERSION}"
: "${ORT_EXTENSIONS_ROOT:?Set ORT_EXTENSIONS_ROOT to the pinned onnxruntime-extensions checkout}"

rm -rf "$BUILD_ROOT"
mkdir -p "$BUILD_ROOT" "$OUTPUT_DIR"

# Microsoft's first-party packaging script. --build_dynamic_framework is a
# supported mode even though Microsoft publishes only the static iOS output.
python3 "$ORT_ROOT/tools/ci_build/github/apple/build_apple_framework.py" \
  "$SCRIPT_DIR/ios_dynamic_build_settings.json" \
  --build_dir "$BUILD_ROOT/ort" \
  --config Release \
  --build_dynamic_framework

readonly ORT_XCFRAMEWORK="$BUILD_ROOT/ort/framework_out/onnxruntime.xcframework"
for slice in ios-arm64 ios-arm64-simulator; do
  test -x "$ORT_XCFRAMEWORK/$slice/onnxruntime.framework/onnxruntime"
  # Do not use grep -q under pipefail: it closes early after the match and
  # causes nm to fail with SIGPIPE on large symbol tables.
  nm -gU "$ORT_XCFRAMEWORK/$slice/onnxruntime.framework/onnxruntime" \
    | grep ' _OrtGetApiBase$' >/dev/null
done

# Extensions needs ORT headers but does not link against ORT: RegisterCustomOps
# receives the API table at runtime. Build only the one non-core op in fonnx's
# real model inventory (Whisper's ai.onnx.contrib:BpeDecoder).
readonly ORT_HEADERS="$BUILD_ROOT/ort-headers"
mkdir -p "$ORT_HEADERS/include"
cp "$ORT_XCFRAMEWORK/ios-arm64/onnxruntime.framework/Headers/"* \
  "$ORT_HEADERS/include/"

readonly SELECTED_OPS_FILE="$ORT_EXTENSIONS_ROOT/cmake/_selectedoplist.cmake"
cleanup() {
  rm -f "$SELECTED_OPS_FILE"
}
trap cleanup EXIT
cat > "$SELECTED_OPS_FILE" <<'CMAKE'
# Generated from fonnx's Whisper graph: ai.onnx.contrib;1;BpeDecoder
set(OCOS_ENABLE_GPT2_TOKENIZER ON CACHE INTERNAL "")
CMAKE

build_extensions_slice() {
  local sdk="$1"
  local output_name="$2"
  local build_dir="$BUILD_ROOT/ortextensions-$output_name"

  cmake -S "$ORT_EXTENSIONS_ROOT" -B "$build_dir" -G Xcode \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT="$sdk" \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$IOS_DEPLOYMENT_TARGET" \
    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO \
    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED=NO \
    -DONNXRUNTIME_PKG_DIR="$ORT_HEADERS" \
    -DOCOS_ONNXRUNTIME_VERSION="$ORT_VERSION" \
    -DOCOS_ENABLE_SELECTED_OPLIST=ON \
    -DOCOS_ENABLE_CTEST=OFF \
    -DOCOS_BUILD_SHARED_LIB=ON
  cmake --build "$build_dir" \
    --config Release --target extensions_shared --parallel 8

  local dylib
  dylib="$(find "$build_dir/lib/Release" -type f \
    -name 'libortextensions.*.dylib' | head -1)"
  test -n "$dylib"
  nm -gU "$dylib" | grep ' _RegisterCustomOps$' >/dev/null
}

build_extensions_slice iphoneos device
build_extensions_slice iphonesimulator simulator
readonly ORTX_DEVICE="$(find "$BUILD_ROOT/ortextensions-device/lib/Release" \
  -type f -name 'libortextensions.*.dylib' | head -1)"
readonly ORTX_SIMULATOR="$(find "$BUILD_ROOT/ortextensions-simulator/lib/Release" \
  -type f -name 'libortextensions.*.dylib' | head -1)"

readonly STAGING="$BUILD_ROOT/staging"
mkdir -p "$STAGING/iphoneos" "$STAGING/iphonesimulator"
cp "$ORT_XCFRAMEWORK/ios-arm64/onnxruntime.framework/onnxruntime" \
  "$STAGING/iphoneos/libonnxruntime.dylib"
cp "$ORT_XCFRAMEWORK/ios-arm64-simulator/onnxruntime.framework/onnxruntime" \
  "$STAGING/iphonesimulator/libonnxruntime.dylib"
cp "$ORTX_DEVICE" "$STAGING/iphoneos/libortextensions.dylib"
cp "$ORTX_SIMULATOR" "$STAGING/iphonesimulator/libortextensions.dylib"

# Avoid carrying local signatures into a release artifact. Flutter's native
# asset embedding signs the final frameworks as part of the app build.
find "$STAGING" -type f -exec codesign --remove-signature {} \; 2>/dev/null || true

readonly ASSET_PATH="$OUTPUT_DIR/$ASSET_NAME"
rm -f "$ASSET_PATH" "$ASSET_PATH.sha256"
(
  cd "$STAGING"
  # -X strips host-specific extra fields. File timestamps remain but integrity
  # is pinned from the uploaded release asset, not predicted in source.
  zip -X -9 -r "$ASSET_PATH" iphoneos iphonesimulator
)
shasum -a 256 "$ASSET_PATH" | tee "$ASSET_PATH.sha256"

cat > "$OUTPUT_DIR/provenance.txt" <<EOF
ORT_VERSION=$ORT_VERSION
ORT_COMMIT=$(git -C "$ORT_ROOT" rev-parse HEAD)
ORTX_COMMIT=$(git -C "$ORT_EXTENSIONS_ROOT" rev-parse HEAD)
IOS_DEPLOYMENT_TARGET=$IOS_DEPLOYMENT_TARGET
XCODE_VERSION=$(xcodebuild -version | tr '\n' ' ')
CMAKE_VERSION=$(cmake --version | head -1)
SELECTED_EXTENSION_OPS=ai.onnx.contrib:BpeDecoder
EOF

printf 'Built %s\n' "$ASSET_PATH"
