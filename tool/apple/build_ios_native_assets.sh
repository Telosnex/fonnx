#!/usr/bin/env bash
# Build the two dynamic native assets required by fonnx on iOS.
#
# Required environment variables:
#   ORT_EXTENSIONS_ROOT  onnxruntime-extensions checkout at ORTX_COMMIT
#
# Supply either:
#   ORT_PREBUILT_ARCHIVE_URL + ORT_PREBUILT_ARCHIVE_SHA256
#     Immutable Apple ORT base previously built by this script, or
#   ORT_ROOT
#     onnxruntime checkout at ORT_VERSION; builds a new dynamic base.
#
# Optional:
#   OUTPUT_DIR           final artifact directory (default: ./dist)
#   BUILD_ROOT           disposable build root (default: $RUNNER_TEMP/fonnx-ios)
#   ORT_VERSION          default 1.27.0
#   ORT_COMMIT           provenance when consuming an immutable base
#   ORTX_COMMIT          provenance label; default is the pinned commit below

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly FONNX_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly ORT_VERSION="${ORT_VERSION:-1.27.0}"
readonly ORTX_COMMIT="${ORTX_COMMIT:-fe4e13f46b19fb490c90b09fe280277308bd5bb7}"
readonly ORT_COMMIT="${ORT_COMMIT:-8f0278c77bf44b0cc83c098c6c722b92a36ac4b5}"
readonly ORT_PREBUILT_ARCHIVE_URL="${ORT_PREBUILT_ARCHIVE_URL:-}"
readonly ORT_PREBUILT_ARCHIVE_SHA256="${ORT_PREBUILT_ARCHIVE_SHA256:-}"
readonly IOS_DEPLOYMENT_TARGET="15.1"
readonly BUILD_ROOT="${BUILD_ROOT:-${RUNNER_TEMP:-/tmp}/fonnx-ios-native-assets}"
readonly OUTPUT_DIR="${OUTPUT_DIR:-$FONNX_ROOT/dist}"
readonly ASSET_NAME="fonnx-ios-arm64-ort-${ORT_VERSION}-ortx-${ORTX_COMMIT:0:8}.zip"

: "${ORT_EXTENSIONS_ROOT:?Set ORT_EXTENSIONS_ROOT to the pinned onnxruntime-extensions checkout}"
readonly ACTUAL_ORTX_COMMIT="$(git -C "$ORT_EXTENSIONS_ROOT" rev-parse HEAD)"
if [[ "$ACTUAL_ORTX_COMMIT" != "$ORTX_COMMIT" ]]; then
  echo "ORT Extensions checkout mismatch: expected $ORTX_COMMIT, got $ACTUAL_ORTX_COMMIT" >&2
  exit 1
fi
if [[ -z "$ORT_PREBUILT_ARCHIVE_URL" ]]; then
  : "${ORT_ROOT:?Set ORT_ROOT or an immutable ORT_PREBUILT_ARCHIVE_URL}"
  readonly ACTUAL_ORT_COMMIT="$(git -C "$ORT_ROOT" rev-parse HEAD)"
  if [[ "$ACTUAL_ORT_COMMIT" != "$ORT_COMMIT" ]]; then
    echo "ORT checkout mismatch: expected $ORT_COMMIT, got $ACTUAL_ORT_COMMIT" >&2
    exit 1
  fi
else
  : "${ORT_PREBUILT_ARCHIVE_SHA256:?Pin ORT_PREBUILT_ARCHIVE_SHA256}"
fi

rm -rf "$BUILD_ROOT"
mkdir -p "$BUILD_ROOT" "$OUTPUT_DIR"

readonly ORT_BINARIES="$BUILD_ROOT/ort-binaries"
mkdir -p "$ORT_BINARIES/iphoneos" "$ORT_BINARIES/iphonesimulator"
if [[ -n "$ORT_PREBUILT_ARCHIVE_URL" ]]; then
  # Reuse only ORT from an immutable artifact previously produced by the full
  # Microsoft-script path below. This keeps Extensions recipe changes fast
  # without turning the consumer hook into a compiler build.
  readonly ORT_PREBUILT_ARCHIVE="$BUILD_ROOT/ort-apple-base.zip"
  curl --fail --location --retry 3 --output "$ORT_PREBUILT_ARCHIVE" \
    "$ORT_PREBUILT_ARCHIVE_URL"
  readonly ACTUAL_ORT_PREBUILT_SHA256="$(
    shasum -a 256 "$ORT_PREBUILT_ARCHIVE" | awk '{print $1}'
  )"
  if [[ "$ACTUAL_ORT_PREBUILT_SHA256" != "$ORT_PREBUILT_ARCHIVE_SHA256" ]]; then
    echo "Apple ORT base SHA-256 mismatch: expected $ORT_PREBUILT_ARCHIVE_SHA256, got $ACTUAL_ORT_PREBUILT_SHA256" >&2
    exit 1
  fi
  unzip -p "$ORT_PREBUILT_ARCHIVE" iphoneos/libonnxruntime.dylib \
    > "$ORT_BINARIES/iphoneos/libonnxruntime.dylib"
  unzip -p "$ORT_PREBUILT_ARCHIVE" iphonesimulator/libonnxruntime.dylib \
    > "$ORT_BINARIES/iphonesimulator/libonnxruntime.dylib"
else
  # Microsoft's first-party packaging script. --build_dynamic_framework is a
  # supported mode even though Microsoft publishes only static iOS output.
  python3 "$ORT_ROOT/tools/ci_build/github/apple/build_apple_framework.py" \
    "$SCRIPT_DIR/ios_dynamic_build_settings.json" \
    --build_dir "$BUILD_ROOT/ort" \
    --config Release \
    --build_dynamic_framework
  readonly ORT_XCFRAMEWORK="$BUILD_ROOT/ort/framework_out/onnxruntime.xcframework"
  cp "$ORT_XCFRAMEWORK/ios-arm64/onnxruntime.framework/onnxruntime" \
    "$ORT_BINARIES/iphoneos/libonnxruntime.dylib"
  cp "$ORT_XCFRAMEWORK/ios-arm64-simulator/onnxruntime.framework/onnxruntime" \
    "$ORT_BINARIES/iphonesimulator/libonnxruntime.dylib"
fi

for binary in \
  "$ORT_BINARIES/iphoneos/libonnxruntime.dylib" \
  "$ORT_BINARIES/iphonesimulator/libonnxruntime.dylib"; do
  test -s "$binary"
  # Do not use grep -q under pipefail: it closes early after the match and
  # causes nm to fail with SIGPIPE on large symbol tables.
  nm -gU "$binary" | grep ' _OrtGetApiBase$' >/dev/null
done

# Extensions needs ORT headers but does not link against ORT: RegisterCustomOps
# receives the API table at runtime. Build only the one non-core op in fonnx's
# real model inventory (Whisper's ai.onnx.contrib:BpeDecoder).
readonly ORT_HEADERS="$BUILD_ROOT/ort-headers"
mkdir -p "$ORT_HEADERS/include"
cp -R "$FONNX_ROOT/onnx_runtime/headers/." "$ORT_HEADERS/include/"

readonly SELECTED_OPS_FILE="$ORT_EXTENSIONS_ROOT/cmake/_selectedoplist.cmake"
readonly BPE_DECODER_ONLY_PATCH="$FONNX_ROOT/tool/extensions/bpe_decoder_only.patch"
git -C "$ORT_EXTENSIONS_ROOT" apply --check "$BPE_DECODER_ONLY_PATCH"
git -C "$ORT_EXTENSIONS_ROOT" apply "$BPE_DECODER_ONLY_PATCH"
cleanup() {
  rm -f "$SELECTED_OPS_FILE"
  git -C "$ORT_EXTENSIONS_ROOT" apply -R "$BPE_DECODER_ONLY_PATCH" \
    >/dev/null 2>&1 || true
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
  strings "$dylib" | grep -x 'BpeDecoder' >/dev/null
  local unexpected_op
  for unexpected_op in \
    GPT2Tokenizer CLIPTokenizer RobertaTokenizer SpmTokenizer HfJsonTokenizer; do
    if strings "$dylib" | grep -x "$unexpected_op" >/dev/null; then
      echo "Unexpected custom op $unexpected_op is present in $dylib" >&2
      exit 1
    fi
  done
}

build_extensions_slice iphoneos device
build_extensions_slice iphonesimulator simulator
readonly ORTX_DEVICE="$(find "$BUILD_ROOT/ortextensions-device/lib/Release" \
  -type f -name 'libortextensions.*.dylib' | head -1)"
readonly ORTX_SIMULATOR="$(find "$BUILD_ROOT/ortextensions-simulator/lib/Release" \
  -type f -name 'libortextensions.*.dylib' | head -1)"

readonly STAGING="$BUILD_ROOT/staging"
mkdir -p "$STAGING/iphoneos" "$STAGING/iphonesimulator"
cp "$ORT_BINARIES/iphoneos/libonnxruntime.dylib" \
  "$STAGING/iphoneos/libonnxruntime.dylib"
cp "$ORT_BINARIES/iphonesimulator/libonnxruntime.dylib" \
  "$STAGING/iphonesimulator/libonnxruntime.dylib"
cp "$ORTX_DEVICE" "$STAGING/iphoneos/libortextensions.dylib"
cp "$ORTX_SIMULATOR" "$STAGING/iphonesimulator/libortextensions.dylib"

# Keep Xcode's linker-generated ad-hoc signature on Extensions. Removing it
# leaves alignment padding at the end of __LINKEDIT for this tiny selected-op
# binary, and install_name_tool then refuses Flutter's framework-ID rewrite.
# Flutter invalidates/replaces the ad-hoc signature while embedding the final
# framework. The reused ORT base is already unsigned and rewrite-safe.

readonly ASSET_PATH="$OUTPUT_DIR/$ASSET_NAME"
rm -f "$ASSET_PATH" "$ASSET_PATH.sha256"
(
  cd "$STAGING"
  # -X strips host-specific extra fields. File timestamps remain but integrity
  # is pinned from the uploaded release asset, not predicted in source.
  zip -X -9 -r "$ASSET_PATH" iphoneos iphonesimulator
)
asset_sha256="$(shasum -a 256 "$ASSET_PATH" | awk '{print $1}')"
printf '%s  %s\n' "$asset_sha256" "$(basename "$ASSET_PATH")" \
  | tee "$ASSET_PATH.sha256"

cat > "$OUTPUT_DIR/provenance.txt" <<EOF
ORT_VERSION=$ORT_VERSION
ORT_COMMIT=$ORT_COMMIT
ORT_PREBUILT_ARCHIVE_URL=$ORT_PREBUILT_ARCHIVE_URL
ORT_PREBUILT_ARCHIVE_SHA256=$ORT_PREBUILT_ARCHIVE_SHA256
ORTX_COMMIT=$ACTUAL_ORTX_COMMIT
IOS_DEPLOYMENT_TARGET=$IOS_DEPLOYMENT_TARGET
XCODE_VERSION=$(xcodebuild -version | tr '\n' ' ')
CMAKE_VERSION=$(cmake --version | head -1)
SELECTED_EXTENSION_OPS=ai.onnx.contrib:BpeDecoder
EOF

printf 'Built %s\n' "$ASSET_PATH"
