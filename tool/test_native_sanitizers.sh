#!/usr/bin/env bash
# Exercise every package-owned finalizer ownership state under ASan + UBSan.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
build="$root/build/finalizer-sanitized"
rm -rf "$build" && mkdir -p "$build"
cc="${CC:-clang}"
"$cc" -std=c11 -O1 -g -Wall -Wextra -Werror \
  -fsanitize=address,undefined -fno-omit-frame-pointer \
  -fno-sanitize-recover=all -I"$root/src" \
  "$root/src/ort_session_finalizer.c" \
  "$root/tool/support/finalizer_boundary_test.c" \
  -o "$build/finalizer_boundary_test"
detect_leaks=1
[[ "$(uname -s)" == Darwin ]] && detect_leaks=0
ASAN_OPTIONS="abort_on_error=1:detect_leaks=$detect_leaks:strict_string_checks=1" \
UBSAN_OPTIONS='halt_on_error=1:print_stacktrace=1' \
  "$build/finalizer_boundary_test"
echo 'PASS: fonnx finalizer boundary under ASan + UBSan'
