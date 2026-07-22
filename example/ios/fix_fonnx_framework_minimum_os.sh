#!/bin/sh
# Flutter 3.44.2's iOS native-assets pipeline generates framework Info.plists
# with Flutter's iOS 13 baseline rather than this Runner target. ORT 1.27's
# Mach-O binaries require iOS 15.1, so the app and wrapper metadata must not
# advertise a lower minimum. See flutter/flutter#145104 and #148044.
set -eu

version_at_least() {
  /usr/bin/awk -v actual="$1" -v required="$2" 'BEGIN {
    split(actual, a, "."); split(required, r, ".")
    for (i = 1; i <= 4; i++) {
      if ((a[i] + 0) > (r[i] + 0)) exit 0
      if ((a[i] + 0) < (r[i] + 0)) exit 1
    }
    exit 0
  }'
}

minimum_os="${IPHONEOS_DEPLOYMENT_TARGET:?IPHONEOS_DEPLOYMENT_TARGET is required}"
frameworks_dir="${TARGET_BUILD_DIR:?TARGET_BUILD_DIR is required}/${FRAMEWORKS_FOLDER_PATH:?FRAMEWORKS_FOLDER_PATH is required}"

if [ "${CODE_SIGNING_ALLOWED:-NO}" = "YES" ] && [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
  signing_identity="$EXPANDED_CODE_SIGN_IDENTITY"
else
  # Flutter ad-hoc signs native-asset frameworks in unsigned local builds too.
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

  binary_mins="$(/usr/bin/xcrun vtool -show-build "$binary" | /usr/bin/awk '/^[[:space:]]*minos / { print $2 }')"
  if [ -z "$binary_mins" ]; then
    echo "error: Could not read the $name Mach-O minimum OS" >&2
    exit 1
  fi
  for binary_min in $binary_mins; do
    if ! version_at_least "$minimum_os" "$binary_min"; then
      echo "error: App minimum '$minimum_os' is lower than $name Mach-O minimum '$binary_min'" >&2
      exit 1
    fi
  done

  /usr/bin/codesign --force --sign "$signing_identity" "$framework"
  /usr/bin/codesign --verify --strict "$framework"
  echo "Aligned $name.framework MinimumOSVersion to $minimum_os"
done
