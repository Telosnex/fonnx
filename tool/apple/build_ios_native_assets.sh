#!/usr/bin/env bash
# Build the dynamic ORT base that fonnx uses on iOS. Microsoft publishes only
# a static iOS ORT.
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

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly FONNX_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly ORT_VERSION="${ORT_VERSION:-1.27.0}"
readonly ORT_COMMIT="${ORT_COMMIT:-8f0278c77bf44b0cc83c098c6c722b92a36ac4b5}"
readonly ORT_PREBUILT_ARCHIVE_URL="${ORT_PREBUILT_ARCHIVE_URL:-}"
readonly ORT_PREBUILT_ARCHIVE_SHA256="${ORT_PREBUILT_ARCHIVE_SHA256:-}"
readonly IOS_DEPLOYMENT_TARGET="15.1"
readonly BUILD_ROOT="${BUILD_ROOT:-${RUNNER_TEMP:-/tmp}/fonnx-ios-native-assets}"
readonly OUTPUT_DIR="${OUTPUT_DIR:-$FONNX_ROOT/dist}"
readonly ASSET_NAME="fonnx-ios-arm64-ort-${ORT_VERSION}.zip"
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
  # Reuse ORT from an immutable artifact previously produced by the full
  # Microsoft-script path below.
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

readonly STAGING="$BUILD_ROOT/staging"
mkdir -p "$STAGING/iphoneos" "$STAGING/iphonesimulator"
cp "$ORT_BINARIES/iphoneos/libonnxruntime.dylib" \
  "$STAGING/iphoneos/libonnxruntime.dylib"
cp "$ORT_BINARIES/iphonesimulator/libonnxruntime.dylib" \
  "$STAGING/iphonesimulator/libonnxruntime.dylib"

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
IOS_DEPLOYMENT_TARGET=$IOS_DEPLOYMENT_TARGET
XCODE_VERSION=$(xcodebuild -version | tr '\n' ' ')
CMAKE_VERSION=$(cmake --version | head -1)
EOF

printf 'Built %s\n' "$ASSET_PATH"
