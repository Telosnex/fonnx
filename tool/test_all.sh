#!/usr/bin/env bash
# Authoritative FONNX package gate. Every Flutter test path is explicit so the
# large model/RSS corpus runs in one serialized process.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

tests=(
  test/deterministic_operation_corpus_test.dart
  test/models/futo_swipe_api_test.dart
  test/models/futo_swipe_converter_test.dart
  test/models/futo_swipe_core_test.dart
  test/models/futo_swipe_test.dart
  test/models/keyword_spotter_core_test.dart
  test/models/keyword_spotter_test.dart
  test/models/magika_test.dart
  test/models/mini_lm_l6_v2_test.dart
  test/models/msmarco_mini_lm_l6_v3_test.dart
  test/models/nemo_asr_test.dart
  test/models/potion32m_test.dart
  test/models/potion8m_test.dart
  test/models/pyannote_test.dart
  test/models/sense_voice_test.dart
  test/models/silero_vad_test.dart
  test/models/whisper_test.dart
  test/ort_native_asset_test.dart
  test/tokenizers/wordpiece_tokenizer_test.dart
  test/wordpiece_tokenizer_perf_test.dart
)

dart run tool/fetch_hf_models.dart
flutter analyze
dart run tool/verify_artifacts.dart
# The browser tests load the web files from lib/web/ (native_prebuilt ADR 002
# D13). Pass a tool/build_web.dart output in FONNX_WEB_FROM to use it.
dart run native_prebuilt:web install-dev ${FONNX_WEB_FROM:+--from "$FONNX_WEB_FROM"}
node tool/test_web_runtime.mjs
tool/test_native_sanitizers.sh
if [[ "$(uname -s)-$(uname -m)" == Darwin-arm64 ]]; then
  tool/test_macos_artifacts.sh
fi
flutter test --concurrency=1 -r compact "${tests[@]}"
# RSS baselines must start in a fresh process. Running them after every other
# hydrated model leaves allocator arenas from unrelated sessions in the same
# process and turns ordinary high-water fluctuations into false leak reports.
flutter test test/models/ort_memory_smoke_test.dart \
  --concurrency=1 -r compact
flutter test test/deterministic_operation_corpus_test.dart \
  test/web_runtime_test.dart --platform chrome -r compact
# dart2wasm. With the default skwasm renderer, the test server sends COOP and
# COEP on the .html page only. The page is then cross-origin isolated, and
# Chrome refuses each model Worker script, because it has no COEP header. The
# CanvasKit renderer keeps the page not isolated, as in the dart2js run.
flutter test test/deterministic_operation_corpus_test.dart \
  test/web_runtime_test.dart --platform chrome --wasm \
  --no-cross-origin-isolation \
  --dart-define=FLUTTER_WEB_USE_SKIA=true \
  --dart-define=FLUTTER_WEB_USE_SKWASM=false -r compact

if [[ "${FONNX_FULL_RUNTIME_MATRIX:-0}" == 1 ]]; then
  tool/test_linux_artifact_docker.sh linux-arm64
  tool/test_linux_artifact_docker.sh linux-x64
  tool/test_windows_artifact_wine.sh
  if [[ "$(uname -s)-$(uname -m)" == Darwin-arm64 ]]; then
    tool/test_ios_simulator_artifacts.sh
    tool/test_android_artifacts.sh
  fi
fi
