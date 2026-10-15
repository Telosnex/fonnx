# Kokoro English development tools

Native streaming is implemented and passes the speech-quality gate in ADR 002.
Web inference is not implemented. Model files remain local and
are ignored by Git; `artifacts.json` records staging hashes, not published URLs.

## Prepare local artifacts

Use Python with these versions: misaki 0.9.4, spaCy 3.8.16,
en_core_web_sm 3.8.0, ONNX 1.23.2, PyTorch 2.14.1, transformers 5.19.0,
NumPy 2.5.4. ONNX Runtime is needed for export verification (tested with 1.31.0).
The Dart runtime still uses the repository's pinned ORT.

```
KOKORO_PYTHON=/path/to/venv/bin/python \
  dart run tool/kokoro/prepare_bundle.dart --tests
```

This downloads all 28 English voices and the source models from a pinned
Hugging Face revision, copies the four English dictionaries, exports the
spaCy tagger and BART fallback, and splits Kokoro into prosody and decoder
stages. Every resulting file must match the staging lock. `--tests` adds the
fp32 reference model. `--record` replaces the lock and is only for a reviewed
artifact update, not for bypassing a mismatch.

The split script is fetched from Moonshine at the ADR's pinned commit and
checked by SHA-256 before execution. Its MIT notice is retained in
`lib/third_party/moonshine_LICENSE.txt`. Source licenses for model and dictionary
artifacts are recorded in the staging lock; final provenance review is still a
release step.

The existing Python exporters are build-time tools. Apps use Dart and ORT only:

| Tool | Purpose |
|---|---|
| `export_spacy_en.py` | Export tokenizer configuration and tagger weights |
| `export_misaki_fallback.py` | Export the pinned BART OOV model |
| `prepare_streaming_models.dart` | Split Kokoro; verify full-render parity and a partial decode |
| `generate_english_goldens.dart` | Run the Python reference for US and GB using the existing corpus generator |
| `generate_chunk_fixtures.dart` | Compile Moonshine's pinned C++ policy to generate acoustic fixtures |

## Use in Dart

```
final kokoro = await Kokoro.load(KokoroBundle.fromDirectory(directory));
try {
  await for (final chunk in kokoro.speak(text, voice: 'af_heart')) {
    // Feed chunk.samples to a 24-kHz mono float PCM player.
  }
} finally {
  await kokoro.dispose();
}
```

The directory factory selects `af_heart` and `bf_emma`. Supply `voiceNames` to
choose other English voices. `input(voice: ...)` accepts fragments through
`add`, `flush`, and `close` and exposes an `audio` stream. Concatenation is
verbatim. Cancellation stops after any in-flight ORT call returns. A paused
consumer retains at most one decoded result; queued text is bounded.

## Validate

Fast and phoneme tests:

```
flutter test test/models/kokoro_chunking_test.dart \
  test/models/kokoro_stream_test.dart test/models/kokoro_test.dart \
  test/models/misaki_en_test.dart test/models/misaki_gb_test.dart
```

The opt-in release test currently fails the ADR's one-percentage-point WER
limit. It writes transcripts to `build/kokoro/quality.json`:

```
flutter test test/models/kokoro_quality_test.dart \
  --dart-define=KOKORO_RELEASE_QUALITY=true
```

It needs the repository's Whisper tiny artifacts too. Do not use the default
skip as evidence that the release gate passed. Review this test, voice listening,
licenses, device results, and artifact publication before landing a release.

The existing root `LICENSE` identifies fonnx as GPLv2. No repository relicensing
was done here. Resolve that with the owner before claiming the complete package
meets the ADR's closed-source distribution requirement.
