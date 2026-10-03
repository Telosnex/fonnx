# FUTO Swipe: English swipe typing and word context

Swipe decoding, next-word prediction, and word scoring from the released FUTO
Swipe models, converted to ONNX. Inference is offline. It needs no Python,
ExecuTorch, or FUTO's GPL swipe library.

The weights are subject to the FUTO Model Weights License 1.0. Products that use
them must display visible **FUTO Swipe** attribution. The bundle carries the
license as `LICENSE-FUTO.txt` and the derivation notice as `NOTICE.txt`.

## Usage

```dart
final swipe = await FutoSwipe.load(
  bundle: FutoSwipeBundle.fromDirectory(modelDirectory),
  lexicon: const [
    FutoSwipeWord('hello', frequency: 200),
    FutoSwipeWord("don't", frequency: 180),
    FutoSwipeWord('Telosnex', frequency: 200), // A personal word.
  ],
);

// Touch points in letter-panel coordinates, oldest first.
final candidates = await swipe.decode(
  points,
  layout: FutoSwipeLayout(renderedKeyCenters), // Default: uniform QWERTY.
  previousWords: const ['I', 'would', 'like', 'to'], // Null: no ContextLM.
);
print(candidates.first.word);

final next = await swipe.predictNextWords(const ['I', 'went', 'to', 'the']);
final tapScores = await swipe.scoreWords(
  const ['see', 'you'],
  const ['tomorrow', 'tomorow'],
);
await swipe.close();
```

## Public contract

- **Coordinates:** `x` and `y` are in the 0–1 range of the letter panel: three
  QWERTY letter rows. Exclude the suggestion strip and the space-bar row.
- **Layout:** `FutoSwipeLayout` takes the centers of keys `a`–`z`. The paired
  decoder is English QWERTY only. Supply rendered centers, not another letter
  arrangement.
- **Trace:** at least one point, with finite coordinates and non-decreasing
  times. Only time differences are used.
- **Lexicon:** each `FutoSwipeWord` keeps its display spelling. Its search key
  is lowercase `a`–`z` with apostrophes removed. Words with other characters,
  such as hyphens or accents, are not swipeable and are skipped.
  `includeModelVocabulary` (default true) adds the 32,768 ContextLM words
  first. `setLexicon` replaces all words atomically.
- **Frequency:** an AOSP-style value from 0 to 255, in the scale that the
  bundle's scoring configuration expects.
- **Candidates:** one candidate per search key. `word` is the best-scoring
  spelling; `alternatives` holds the others. `score` is a natural-log ranking
  score, not a probability or a confidence.
- **Context:** ContextLM reads the last 16 previous words. An empty list scores
  the start of text. A null `previousWords` disables ContextLM. Each setting
  uses its matching weights from `scoring.json`.
- **Platforms:** Android, iOS, Linux, macOS, and Windows use the shared ONNX
  Runtime Dart FFI backend in one long-lived isolate. The Web runs the graphs in
  a Worker and the lexicon search on the page thread. Include
  `futo_swipe_init.js` and `futo_swipe_worker.js` in the Web application.

## Pipeline

1. **Resampling.** Interpolate the trace linearly in time to about 60 Hz, then
   by index to 64 points. A trace with no duration skips the first stage. The
   Dart arithmetic follows `numpy.linspace` and `numpy.interp`. It reproduces
   the validation features bit-for-bit for all 1,000 replay traces.
2. **Encoder** (`honorable_sturgeon`). It takes `features [1,2,64]`,
   `layout_keys [1,64,2]`, and `layout_mask [1,64]`. It returns log emissions
   `[1,32,65]`, coefficients `[1,32,64]`, and intention `[1,32,1]`.
3. **Decoder** (`magic_macaw`). Each step's input is 26 letter emissions, the
   blank (encoder index 64), 64 coefficients, and the intention. The output is
   `[1,32,27]`: `a`–`z`, then the blank.
4. **Search.** A trie-constrained CTC prefix search with length-normalized
   pruning. It keeps separate blank- and letter-ending mass per prefix and
   checks the recurrence against exhaustive enumeration. The beam width
   defaults to 300.
5. **Ranking.** The score is `ctc / length^gamma + beta * length + lambda *
   frequency`. With context, the score adds `alpha * context`.
6. **ContextLM** (`hungry_jellyfish`). It takes right-padded token IDs
   `[1,16]` and hash buckets `[1,16,2]`. It returns the states `[1,16,16]`.
   The engine reads the final real position and caches it until the context
   changes. A word scores as an embedding dot product plus a bias. A word that
   is not in the vocabulary uses the sum of its two hashed rows. The last
   vocabulary line has no exact row, so it is hashed too.

The hash for words outside the vocabulary is a model-specific variant of the
wyhash family. Do not substitute a standard wyhash library. Reference vectors
in `test/models/futo_swipe_core_test.dart` cover block boundaries and UTF-8.

## Validation

- **1,000 public swipes:** `tool/futo/replay.dart` sends the raw traces through
  `FutoSwipe.decode`. It returns the same ordered top-three candidates as
  ExecuTorch for all 1,000 swipes, without context. Top-1 is 886/1,000 and
  top-3 is 914/1,000. On an Apple M4 Max, decoding takes 15.9 ms at the median
  and 22.9 ms at p95. This includes the Dart search over a 253,219-spelling
  lexicon.
- **Model outputs:** the native backend is within tolerance of nine ExecuTorch
  goldens. The four embedding tables match byte-for-byte.
- **Web:** under Node, ONNX Runtime Web 1.27.0 ran the Worker. Its outputs met
  the same golden tolerances, and the embeddings matched byte-for-byte. The
  compiled Dart Web API also matched native results on 20 swipes. It did not
  run in a browser.
- **Untested:** Pi, Android, and iOS execution. Context-enabled replay
  accuracy has no frozen ExecuTorch reference in this package.

```bash
flutter test test/models/futo_swipe_core_test.dart test/models/futo_swipe_api_test.dart test/models/futo_swipe_test.dart
flutter test tool/futo/replay.dart --concurrency=1 --reporter expanded  # Network.
```
