#!/bin/sh
# Flutter currently gives generated iOS native-asset framework wrappers its
# global minimum (13.0), regardless of the consuming app's deployment target.
# FONNX's ORT 1.27 binaries require 15.1, so App Store validation rejects the
# wrappers unless their Info.plists agree with both the app and Mach-O binaries.
set -eu

minimum_os="${IPHONEOS_DEPLOYMENT_TARGET:?IPHONEOS_DEPLOYMENT_TARGET is required}"
frameworks_dir="${TARGET_BUILD_DIR:?TARGET_BUILD_DIR is required}/${FRAMEWORKS_FOLDER_PATH:?FRAMEWORKS_FOLDER_PATH is required}"

if [ "${CODE_SIGNING_ALLOWED:-NO}" = "YES" ] && [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
  signing_identity="$EXPANDED_CODE_SIGN_IDENTITY"
else
  signing_identity="-"
fi

for name in onnxruntime ortextensions; do
  framework="$frameworks_dir/$name.framework"
  plist="$framework/Info.plist"
  binary="$framework/$name"

  if [ ! -f "$plist" ] || [ ! -f "$binary" ]; then
    echo "error: Missing FONNX native-asset framework: $framework" >&2
    exit 1
  fi

  /usr/bin/plutil -replace MinimumOSVersion -string "$minimum_os" "$plist"

  binary_min="$(/usr/bin/xcrun vtool -show-build "$binary" | /usr/bin/awk '/^[[:space:]]*minos / { print $2; exit }')"
  if [ -z "$binary_min" ] || [ "$binary_min" != "$minimum_os" ]; then
    echo "error: $name Mach-O minimum '$binary_min' does not match app minimum '$minimum_os'" >&2
    exit 1
  fi

  /usr/bin/codesign --force --sign "$signing_identity" "$framework"
  /usr/bin/codesign --verify --strict "$framework"
  echo "Aligned $name.framework MinimumOSVersion to $minimum_os"
done
