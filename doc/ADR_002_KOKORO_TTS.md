# ADR 002 — English Kokoro text to speech in fonnx
Status: DRAFT

## 1. Problem

The working tree contains an American English proof of concept. It runs
Kokoro-82M v1.0 through FFI and produces audio from text through a Dart misaki
port. Its phonemes match Python on 1,096 sentences.

An app cannot use it through a public API. There is no worker isolate,
streaming API, long-input handling, or web implementation. Data files exist
only on the local disk. British English has no reference tests yet.

The proof of concept also needs two corrections:

- `num2words_en.dart` translates LGPL-2.1 code. It cannot ship under R1.
- The voice style row differs from the PyTorch reference. The reference uses
  `pack[len(ps) - 1]`, where `ps` is the stripped phoneme string.

This release covers American and British English. It uses Moonshine's
chunking algorithm, ported to Dart. No non-English phonemizer is in scope.

## 2. Requirements

| ID | Requirement | Source | Hardness |
|----|-------------|--------|----------|
| R1 | No GPL or LGPL code or data ships in fonnx or its downloaded files. | license | hard |
| R2 | Audio streams before synthesis of the complete input finishes. | founder | hard |
| R3 | Model and phoneme work never runs on the UI isolate. | platform | hard |
| R4 | American and British English pass reference and speech tests. | assumed | hard |
| R5 | Support macOS, Windows, Linux, iOS, and Android. | assumed | hard |
| R6 | Support web. fonnx offers every model on every platform. | founder | hard |
| R7 | Publish artifacts under ADR 001, with SHA-256 pins in Git. | ADR001 | hard |
| R8 | Record and ship required licenses and attribution. | license | hard |
| R9 | American English synthesis exceeds real-time speed on a Raspberry Pi 5. | assumed | soft |
| R10 | Download only the English dialect data and voices the app uses. | assumed | soft |
| R11 | Support English only: American and British English. | founder | hard |
| R12 | Use Moonshine's chunking algorithm. | founder | hard |

## 3. Decisions

```
D1: Use Kokoro-82M v1.0 and the onnx-community ONNX export. Start from the
    proof of concept's model_uint8.onnx. Derive prosody and decoder stages
    for D9. Keep the whole model as a test reference only. The package
    does not ship or load it.
    Because: R2, R5, R9, R12
    Instead of: replacing the TTS engine. The English proof of concept works.
    Instead of: assuming the smallest quantization is fastest. Measure the
    split stages on fonnx's pinned ORT before publishing them.

D2: Support only American English (a) and British English (b). Use the Dart
    misaki port for both, with dialect-specific dictionaries.
    Because: R1, R5, R6, R11
    Instead of: multilingual support. It adds phonemizers and dependencies
    that this release does not need.

D3: Use the BART fallback for unknown words, not espeak-ng. Pin its weights
    and the misaki reference revision.
    Because: R1, R4
    Instead of: upstream Kokoro's espeak-ng fallback. It fails R1.
    The fallback targets US English. British English requires separate
    unknown-word listening checks, not just dictionary parity tests.

D4: Keep text normalization separate from the misaki port. Add explicit
    handling for clock times, URLs, e-mail addresses, units, and symbols.
    Because: R4
    Instead of: changing misaki rules and invalidating its reference tests.

D5–D7: Withdrawn in this draft. Non-English phonemizers are outside R11.

D8: Select the voice style row as the PyTorch reference does. Regenerate
    the inference goldens with that rule.
    Because: R4
    Instead of: retaining the proof of concept's different row selection.

D9: Port Moonshine's sentence splitter, phoneme length splitter, and sliced
    decoder stream to Dart. Pin the source revision in section 5 and retain
    its MIT notice. Run prosody once per utterance, then decode padded frame
    slices. Use its boundary cost, growing schedule, and crossfade.
    Because: R2, R12
    Instead of: the previous custom 20/100–200/400-token policy. It is not
    Moonshine's algorithm.
    Instead of: slicing a finished waveform. That does not reduce the time
    to first audio.
    Oversized utterances use Moonshine's phoneme splitter before inference.
    Each piece is decoded in slices. There is no whole-model fallback.
    Instead of: a whole-model fallback. Sliced decoding passes the D14
    gate, and a fallback would add a second 90 MB model.

D10: Use a long-lived native isolate or web worker. Keep model sessions and
     phonemizer data there. Expose a Kokoro API with these operations:
       load(bundle)
       speak(text, voice, speed) -> Stream<KokoroChunk>
       synthesize(text, voice, speed) -> complete PCM
       input(voice, speed) -> text sink and audio stream
       dispose()
     The input sink supports add, flush, and close. Serialize synthesis so
     requests cannot overwrite each other's prosody state. Cancellation
     discards queued text and results for that request. Bound the output
     queue so a paused consumer cannot cause unbounded audio generation.
     The voice sets the language: each bundle voice has one.
     On web, the worker engine is the same Dart code, compiled to
     JavaScript. tool/kiln/build_web.dart writes it as the generated web file
     kokoro_engine.dart.js. ORT Web is asynchronous, so the fallback model
     cannot answer misaki synchronously. The engine runs misaki again with
     the fallback words that it computed, until misaki asks for no new word.
     Because: R2, R3
     Instead of: a language argument. A British voice with American
     phonemes, or the reverse, has no use.
     Instead of: sessions per chunk, or synthesis on the UI isolate.
     Playback remains the app's responsibility.

D11: Publish a shared English tagger and fallback bundle. Keep US and GB
     dictionaries separate. Publish each English voice as a separate file.
     Both dialects share the Kokoro stages.
     Because: R7, R10
     Instead of: a multilingual download or local-only files.

D12: Record the license and provenance of each artifact. Ship attribution
     with downloaded bundles and expose it to apps. Retain the MIT notice
     for Moonshine's ported code.
     Because: R1, R8
     Instead of: assuming the code license covers model and dictionary data.

D13: Port the English phonemizer and chunking to web. Use a hash
     implementation with identical results on the VM and JavaScript.
     Because: R6
     Instead of: assuming Dart int preserves native 64-bit hash behavior
     after compilation to JavaScript.

D14: Require exact phoneme parity against pinned references for both
     dialects. Compare the full split-model render with the whole model
     before testing partial decoding. Sliced audio need not equal the whole
     waveform. Port Moonshine's boundary, span, crossfade, and stream tests.
     Compare chunked and whole audio on the same fixed English corpus and
     voices. Parakeet TDT v3 word error rate can increase by at most one
     percentage point. Listening checks must find no missing words, clicks, or obvious
     level jumps. Record first-audio latency and sustained decode speed.
     Because: R2, R4, R12
     Instead of: treating waveform differences alone as proof of bad speech,
     or treating a successful model run as proof of acceptable speech.

D15: Replace the LGPL-derived number converter with independently written
     code. Preserve the outputs needed by misaki through behavioral tests.
     Review provenance before release.
     Because: R1, R4
     Instead of: distributing a translated copy under the fonnx license.
```

## 4. Invariants

```
I1: US and GB phonemes match their pinned misaki reference goldens.
    If violated: the model receives different pronunciation inputs.
    Pinned by: test/models/misaki_en_test.dart, extended for GB.

I2: spaCy tokens and tags match the reference on native and web.
    If violated: misaki selects different pronunciations.
    Pinned by: tokenizer and tagger fixtures on the VM and Chrome.

I3: Every model input has at most 510 phoneme tokens plus boundary tokens.
    If violated: long input truncates or fails.
    Pinned by: phoneme splitter fixtures and long-input property tests.

I4: Every published artifact has reviewed license and provenance metadata.
    If violated: R1 or R8 fails.
    Pinned by: artifact verification and a release license review.

I5: Whole fp32 inference matches Python onnxruntime within 2e-3 per sample.
    The complete split-model render must pass a separate numerical parity
    check against its source model before partial decode tests.
    If violated: style selection, inference, or graph export is wrong.
    Pinned by: test/models/kokoro_test.dart and export verification fixtures.

I6: Native sessions and inference run outside the UI isolate.
    If violated: speech generation blocks the UI.
    Pinned by: worker lifecycle and session-factory tests.
    On web, sessions, phonemes, and chunking run in one Web Worker.
    Pinned by: test/models/kokoro_web_test.dart (timer ticks on the page).

I7: With D9's deviations off, frame boundaries, decode spans, and emitted
    sample counts match the pinned Moonshine implementation. The shipped
    policy adds the pause guard, so its seams can differ. Flush and close
    preserve pending text.
    If violated: the port changes chunking or loses speech.
    Pinned by: C++ reference fixtures and Dart chunking and stream tests.

I8: Streamed PCM contains no overlapping or missing samples at joins.
    Retain the crossfade tail until the next slice, then emit it once.
    If violated: playback repeats audio or contains gaps.
    Pinned by: synthetic slice, final-tail, and cancellation tests.
```

## 5. Formats and names

- Reference model: `kokoro_v1.0_uint8.onnx`.
- Streaming stages: `kokoro_v1.0_uint8_prosody.onnx` and
  `kokoro_v1.0_uint8_decoder.onnx`. Validate parity and performance before
  publication. Artifact naming and hashes follow ADR 001.
- Prosody interface: `input_ids`, `style`, `speed` -> `asr [1,512,T]`,
  `f0 [1,2T]`, `n [1,2T]`. Decoder inputs: `asr`, `f0`, `n`, `style`.
  Crossing tensors are float32. Output is mono float PCM at 24 kHz.
- Voice files: `kokoro_v1.0_voice_<name>.bin`, with little-endian float32
  values. Validate the shape and length against the pinned upstream assets.
- English data: dialect-specific `us_*` and `gb_*` dictionaries, shared
  spaCy configuration and weights, and shared BART fallback model and tables.
- Voice names set the language: `a[fm]_*` -> `en-US`, `b[fm]_*` -> `en-GB`.
  Reject other names. Do not silently label them English.
- `KokoroChunk` contains PCM, sample rate, utterance ID, and `isFinal`.
  Text and phonemes belong on the first chunk of an utterance only.
  Acoustic slices do not establish word alignment.
- Source: `lib/models/kokoro/`. Keep the English port in `misaki/`.

### Pinned Moonshine algorithm

Repository: `moonshine-ai/moonshine`.
Commit: `234f60faa0eb388b01cdf7e60aca232af37aefda`.

Source under `core/moonshine-tts/src/`:

- `sentence-splitter.{h,cpp}`
- `chunk-policy.{h,cpp}`
- `tts-stream.{h,cpp}`
- `chunk_phonemes` in `moonshine-tts.cpp`

Use the corresponding tests as reference fixtures. Inspect the graph export
in `scripts/split-kokoro-stages.py`, and verify it against the selected model.

Defaults from that revision:

- First acoustic chunk: 0.6 s. Boundary search tolerance: 0.2 s.
- Growth: 2.0. Padding: 8 frames per side. Crossfade: 0.025 s.
- Deviation: no seam in a pause. A seam must have 4 speech frames (prosody
  energy above 2) in the 8 frames after it and 4 in the 8 before it.
  Leading and trailing pauses join the first and last slices. Moonshine's
  boundary cost is lowest where a word fades into a pause, so it often puts
  seams there. A slice that starts or ends in a pause decodes noise, often a
  short burst. In 97 seams from Infinite Jest chapter 1 (`af_heart`), 3 had
  audible clicks; with the change, 0 of 92. The same text shows 0 clicks
  with `am_michael`, `bf_emma`, and `am_onyx`. With a guard on the start
  side only, `am_michael` put the first seam in its longer leading silence
  in 20 of 35 sentences.
- Deviation: each decode window holds at least 40 speech frames (1 s). The
  window grows, alternately before and after, past the 8 padding frames;
  the kept range does not change. The decoder normalizes over its whole
  input, so a slice with little speech decodes its pauses as loud noise. In
  "Mr. Darcy paid $5.99 for three tickets." (`bf_emma`), the last slice is
  "ts" and a 0.7 s pause; it decoded as a breath-like noise at -65 to
  -75 dB, where one whole-sentence decode is near silence. Against
  whole-sentence decodes of 10 sentences (`bf_emma`, `af_heart`), the worst
  20 ms excess fell from 56 dB to 17 dB. 40 padding frames per side reach
  23 dB. Total decode time rose 14% (4.9 s to 5.6 s); 40 padding frames
  cost 55%. First audio rose from about 110 ms to 155 ms on an M-series
  Mac. The growth limit is unchanged: the minimum window is a fixed cost
  per slice, so slower growth cannot pay for it. A device whose decode
  costs more than about 0.5 s per second of audio can play the first slice
  before the second is ready. A longer first slice is the remedy there.
- Kokoro: 40 frames/s, 600 samples/frame.
- Port the sustainable-growth calculation, including padding cost.
- Sentence splitting: English abbreviation rules, colon splitting enabled,
  and `min_codepoints = 0`. Deviation: an open quote or bracket is a flag
  that any closer clears, `’` closes quotes, and the flag stops holding
  sentence ends after 500 characters. Moonshine's matching lets one
  unmatched mark stop all later splits: in a scan of Infinite Jest, one
  "sentence" held 480,460 words. With the change, the largest is 760.
  A spaced ellipsis (". . .") is one mark, like "...". Moonshine splits
  it into one-period sentences: 206 in Infinite Jest, 62 with the change.
  Most of the 62 are silent replies (`'...’`) or scan damage.
- Preserve incomplete text until more input, flush, or close. Concatenate
  incoming fragments verbatim.
- Phoneme limit: 510 code points before boundary tokens. Split at the last
  space within the limit, or at the limit when no space exists.

## 6. Non-goals

```
NG1: Voice cloning.
     Reopens when: an app requests custom voices.

NG2: Non-English support, including Mandarin-specific Kokoro models.
     Reopens when: the founder requests a named language. Its phonemizer,
     voices, and licenses require a separate decision.

NG3: Native phonemizer dependencies such as MeCab or Open JTalk.
     Reopens when: an approved non-English language requires one.

NG4: SSML. Keep misaki's existing pronunciation override syntax.
     Reopens when: an app needs markup beyond that syntax.

NG5: Changes to model training or architecture.
     Reopens when: split export cannot meet D14 and a new design is approved.
```

## 7. Risks

1. **License provenance.** Remove the LGPL-derived number converter before
   release. Review data licenses separately from code licenses.
2. **Sliced audio differs from whole audio.** Decoder normalization depends
   on slice length. Growth and padding reduce the effect but do not produce
   identical waveforms. D14 is a release gate.
3. **Memory and decode speed.** Measure both on target devices. The default
   growth rate can outrun a slow decoder. Use Moonshine's sustainability
   calculation and report whether generation keeps pace with playback.
4. **British fallback accent.** The fallback targets US English. Dictionary
   parity alone does not establish British unknown-word quality.
5. **Upstream drift.** Pin misaki, spaCy, fallback weights, and Moonshine code.
   Updates require new reference fixtures and quality measurements.
6. **Conflicting upstream comments.** At the pinned revision, the graph export
   script says slicing was rejected. The runtime enables it and explains
   why the earlier metric was rejected. Reproduce the measurements.

## 8. Workplan

### Phase 1: English, native

1. Replace the LGPL-derived number converter. Preserve its behavioral tests.
2. Correct voice row selection and regenerate the inference goldens.
3. Add British dictionaries and goldens. Check unknown-word pronunciation.
4. Add the separate text normalizer and its tests.
5. Port Moonshine's sentence and phoneme splitters. Add long-input tests.
6. Export the prosody and decoder stages. Verify full-render parity on the
   pinned ORT version. Record artifact provenance and interfaces.
7. Port Moonshine's chunk policy and sliced stream, including crossfade tail
   handling and sustainable growth. Add reference fixtures for I7 and I8.
8. Add the worker API, bounded queues, flush, cancellation, and disposal.
9. Pass the speech and listening checks in D14 before publication.
10. Publish both stages, English data, and English voices through ADR 001.
    Add license and provenance checks to artifact verification.
11. Add the example app panel: text input, voice list, and streamed playback.
12. Measure first-audio latency, real-time factor, and peak memory on the Pi 5
    and a low-end Android phone. Check sustained playback, not only one chunk.
13. Verify bundle loading, streaming, cancellation, and disposal on all five
    native platforms.

### Phase 2: web

1. Make spaCy hashes identical on the VM and JavaScript. Run the tagger tests.
2. Add the Kokoro web worker with both stages.
3. Run the same chunking fixtures and speech checks in Chrome.

## ──────── non-normative ────────

### A. Alternatives and notes

- **Two levels of chunking.** Moonshine discovers utterances from incremental
  text, then splits their acoustic frames. D9 ports both levels.
- **No grammar tags.** The proof of concept's simplified tag test changed
  phonemes in 656 of 1,096 sentences. Retain the spaCy tagger.
- **No Moonshine runtime dependency.** Port its MIT chunking code. Its model
  and data licenses are separate from its source license.
- **Source links at the pinned revision:**
  - https://github.com/moonshine-ai/moonshine/blob/234f60faa0eb388b01cdf7e60aca232af37aefda/core/moonshine-tts/src/chunk-policy.cpp
  - https://github.com/moonshine-ai/moonshine/blob/234f60faa0eb388b01cdf7e60aca232af37aefda/core/moonshine-tts/src/sentence-splitter.cpp
  - https://github.com/moonshine-ai/moonshine/blob/234f60faa0eb388b01cdf7e60aca232af37aefda/core/moonshine-tts/src/tts-stream.cpp
  - https://github.com/moonshine-ai/moonshine/blob/234f60faa0eb388b01cdf7e60aca232af37aefda/LICENSE

### B. Open questions for the founder

1. Is web required for the first release? Answered: yes. fonnx offers every
   model on every platform (R6).
2. Is the Pi 5 the right minimum device, or is a specific phone the target?

### C. Revision history

- 2026-10-14: First draft, after the English proof of concept.
- Draft revision: The founder limited this release to English and selected
  Moonshine's chunking. Removed non-English implementation phases. Pinned
  the Moonshine source and added split-model and stream release gates.
- Web revision: R6 is hard. The founder requires every fonnx model on every
  platform. Added the web Worker design to D10 and I6.

### D. Implementation checkpoint — native English

**Web, phase 2 steps 1 and 2 (local, not released):** spaCy hashes use two
32-bit halves (`spacy_hash.dart`). Tokens, tags, and US and GB phonemes match
Python in Chrome (`test/models/misaki_web_test.dart`, every 10th sentence).
The Kokoro web Worker passes `test/models/kokoro_web_test.dart`.
Step 3: the chunking fixtures (`test/models/kokoro_chunking_test.dart`) pass
in Chrome. Web and native run the same Dart engine, so the quality gate runs
on native only; the web test checks that web audio matches native (envelope
correlation 0.996 or more). Phonemes,
including fallback-model words, are equal to native. With a fixed span plan,
sample counts are equal and loudness envelopes correlate at 0.99 or more.
The native engine uses the same Dart engine code and passes the release
quality gate. `kokoro_engine.dart.js` is a generated file. It reaches apps
only after the next native release.

Implemented locally:

- Independent base-1000 number conversion, corrected style row, US and GB
  phoneme parity, and separate text normalization.
- Moonshine sentence and phoneme splitting, acoustic boundary costs, growing
  frame spans, and incremental crossfade output. C++-generated fixtures pin
  the acoustic policy to the selected revision.
- Prosody/decoder FFI, long-lived worker, pull-based audio, bounded text input,
  flush, cancellation, disposal, and a native example preview.
- All 28 English voice files prepared locally. A reproducible preparation tool
  and staging artifact hashes are in `tool/kokoro/`. No model was published.

**Speech evaluation:** passes. The first runs used Whisper tiny, which made
errors of its own at seams that a human does not hear. On the same 64
sentences (1,240 words per voice), Whisper tiny measured +1.6 points
(`af_heart`) and +2.7 (`bf_emma`); Parakeet TDT v3 measured +0.2 and +0.6.
The gate now uses Parakeet on 88 sentences (945 words per voice): the 8
original regression sentences, then a stride through reference sentences of
8 to 14 words, which have the most seams per second. Results: `af_heart`
6.46% whole, 7.41% streamed (+0.95); `bf_emma` 6.67%, 6.46% (-0.21). Before
the 40-speech-frame decode window, the same run gave +0.74 and +0.32.
Whole-sentence transcripts are in `test/data/goldens/kokoro_quality_whole.json`,
so a run renders only the streamed audio (about 2 minutes). Word errors do not
show clicks: a policy with no crossfade scored the same as the shipped one.
Clicks need listening checks. In a blind check of Infinite Jest chapter 1
(`af_heart`), the founder heard no clicks or other problems, including at
the loudest remaining burst candidate (199.5 s).

The expensive gate is explicit:

```
flutter test test/models/kokoro_quality_test.dart \
  --dart-define=KOKORO_RELEASE_QUALITY=true
```

Add `--dart-define=KOKORO_QUALITY_UPDATE=true` to make the whole-sentence
transcripts again after a model, voice, phoneme, or recognizer change.

Five-platform/device checks and full voice listening checks are not
complete. The example preview plays individual WAV chunks; applications
need a continuous PCM player for gapless output.

**Publication:** the 38 bundle files (two model stages, 28 English voices,
dictionaries, fallback model and spaCy data; 214 MB) are on Hugging Face
`telosnex/fonnx` at commit `4322a6e7ef82e0e483ad795466f60e370701cba0`, pinned
in `native_artifacts/manifest.json`. The model card lists the source and
license of each file. All are Apache-2.0 except the spaCy data (MIT).

**Existing repository license:** the root `LICENSE` identifies fonnx itself as
GPL version 2. Replacing the LGPL-derived number converter does not change that
package license. R1 therefore also needs an owner-reviewed licensing decision
before a closed-source distribution. This task does not change `LICENSE`.
