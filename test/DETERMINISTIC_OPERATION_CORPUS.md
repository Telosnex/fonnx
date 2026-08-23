# Deterministic operation corpus v1

This 21-recipe corpus complements—not replaces—the checked-in model outputs,
Kaldi reference features, diarization/VAD goldens, Magika file corpus, and RSS
smoke tests.

Stable `v1/` cases isolate package-owned behavior:

- eight streaming-fbank chunk boundaries, including 1, 159/160/161, and prime
  chunk lengths, compared byte-for-byte with one-shot frontend output;
- eight Magika 512-byte boundary sizes compared with an independent extractor;
- signed PCM16 extrema;
- Whisper timestamp cleanup;
- deep call-time snapshots of keyword/spoken-form lists;
- NaN, infinity, empty, and out-of-range keyword configuration.

The source signal is generated from fixed frequencies and impulses. Recipe IDs
include a major version so intentional semantic changes create `v2` rather than
silently moving expectations.

The corpus runs on the Dart VM, Chrome JavaScript, and Chrome Wasm. Actual model
inference remains covered separately by hydrated ONNX goldens and by the pinned
ORT Web identity smoke test.
