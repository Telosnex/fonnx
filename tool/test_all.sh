#!/usr/bin/env bash
# Authoritative FONNX package gate. Every Flutter test path is explicit so the
# large model/RSS corpus runs in one serialized process.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

tests=(
  test/deterministic_operation_corpus_test.dart
  test/models/keyword_spotter_core_test.dart
  test/models/keyword_spotter_test.dart
  test/models/magika_test.dart
  test/models/mini_lm_l6_v2_test.dart
  test/models/msmarco_mini_lm_l6_v3_test.dart
  test/models/potion32m_test.dart
  test/models/potion8m_test.dart
  test/models/pyannote_test.dart
  test/models/silero_vad_test.dart
  test/models/whisper_test.dart
  test/ort_native_asset_test.dart
  test/tokenizers/wordpiece_tokenizer_test.dart
  test/wordpiece_tokenizer_perf_test.dart
)

flutter analyze
dart run tool/verify_artifacts.dart
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
  --platform chrome -r compact
flutter test test/deterministic_operation_corpus_test.dart \
  --platform chrome --wasm -r compact

if [[ "${FONNX_FULL_RUNTIME_MATRIX:-0}" == 1 ]]; then
  tool/test_linux_artifact_docker.sh linux-arm64
  tool/test_linux_artifact_docker.sh linux-x64
  tool/test_windows_artifact_wine.sh
  if [[ "$(uname -s)-$(uname -m)" == Darwin-arm64 ]]; then
    tool/test_ios_simulator_artifacts.sh
    tool/test_android_artifacts.sh
  fi
fi
