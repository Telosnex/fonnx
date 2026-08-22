# English open-vocabulary keyword spotting

Runtime-configurable wake phrases using the Apache-2.0, 3.3M-parameter
GigaSpeech Zipformer model. Phrases are selected locally at runtime; model
training, voice enrollment, Python, sherpa-onnx, and network access are not
required.

## Usage

```dart
final spotter = await KeywordSpotter.load(
  bundle: KeywordSpotterBundle.gigaSpeech3m(modelDirectory),
  keywords: const [
    KeywordPhrase(
      'telosnex',
      spokenForms: ['tell us next', 'tell us nucks', 'tell us necks'],
    ),
  ],
);

spotter.detections.listen((event) {
  print('Detected ${event.phrase}');
});

await spotter.acceptPcm16(microphoneBytes, sampleRate: 16000);
await spotter.close();
```

Call `finish` at the end of a finite recording so the final partial feature
frames and trailing-blank confirmation are processed. `setKeywords` atomically
replaces all phrases and resets decoder context. `transcribePcm16` and
`transcribeSamples` can be used to discover useful `spokenForms` for names and
brands.

## Public contract

- Audio: mono, 16 kHz; `acceptPcm16` expects signed little-endian PCM.
- Phrases: English A-Z, apostrophe, hyphen, and whitespace only.
- Model: `sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01`, using its
  three int8 ONNX graphs.
- Runtime phrase changes require no training or network access.
- Names and brands can provide `spokenForms`; detections still return the
  canonical `KeywordPhrase.text`.
- Android, iOS, Linux, macOS, and Windows: the same ONNX Runtime Dart FFI
  implementation in a long-lived isolate, with libraries supplied by Native
  Assets. There are no model-specific Kotlin or Swift runners. ORT 1.27.0's
  Apple SME convolution bug is disabled for these Zipformer sessions.
- Web: ONNX Runtime Web in a worker with the shared Dart decoder; include
  `fonnx_kws_init.js` and `fonnx_kws_worker.js` in the application.

## Model bundle

Obtain the original model from the
[sherpa-onnx KWS release](https://github.com/k2-fsa/sherpa-onnx/releases/tag/kws-models).
The source archive is named
`sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01.tar.bz2`; its SHA-256 is:

```text
f170013b4716e41b62b9bfd809687c207cef798ef9bc6534d524e17af9b6561a
```

Pass the extracted directory to `KeywordSpotterBundle.gigaSpeech3m`. FONNX
loads these files:

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| `encoder-epoch-12-avg-2-chunk-16-left-64.int8.onnx` | 4,807,159 | `1e721676515bcd42a186979733981213c66c80db680e1cc582dfedf3be76e678` |
| `decoder-epoch-12-avg-2-chunk-16-left-64.int8.onnx` | 277,985 | `e40ff43297abe815e8898494c17e71bba2152d9d40fa3eb803f75d0f7533329a` |
| `joiner-epoch-12-avg-2-chunk-16-left-64.int8.onnx` | 163,380 | `eae9da0c7e1e6c6a3f4cc42d167899c388f6c6701b94cb96320e4f55df79624c` |
| **Total shipped graphs** | **5,248,524** | |

The original `bpe.model` and `tokens.txt` were used to generate the checked-in
Dart English vocabulary and tokenizer; applications do not load or ship them.

## Runtime model contract

### Audio frontend

The Dart frontend matches `kaldi-native-fbank` v1.20.0:

- normalized float samples in `[-1, 1]` at 16,000 Hz;
- 80 mel bins, 25 ms frames, and a 10 ms frame shift;
- 20 Hz low frequency and 7,600 Hz high frequency;
- no dither, `snip_edges: false`, DC offset removal, 0.97 pre-emphasis, and a
  Povey window.

The streaming fixture compares selected frames across a full utterance. The
reference generation measured a maximum absolute difference of `3.53e-5` from
kaldi-native-fbank.

### Encoder

The primary input is `x: float32 [batch, 45, 80]`. There are 38 state inputs
and matching outputs: six tensors for each of six encoder layers, plus
`embed_states: float32 [batch, 128, 3, 19]` and
`processed_lens: int64 [batch]`. Initial states are zero and their shapes are
derived from the model metadata. Relevant metadata is:

```text
model_type=zipformer2
T=45
decode_chunk_len=32
left_context_len=64,32,16,8,16,32
encoder_dims=128,128,128,128,128,128
query_head_dims=32,32,32,32,32,32
value_head_dims=12,12,12,12,12,12
num_heads=4,4,4,8,4,4
num_encoder_layers=1,1,1,1,1,1
cnn_module_kernels=31,31,15,15,15,31
```

The host supplies 45 fbank frames when ready and advances by 32 frames per
encoder call, or about one call per 320 ms after startup context is available.

### Decoder and joiner

```text
decoder input  y:           int64   [batch, 2]
decoder output decoder_out: float32 [batch, 320]
joiner input   encoder_out: float32 [batch, 320]
joiner input   decoder_out: float32 [batch, 320]
joiner output  logit:       float32 [batch, 500]
```

Decoder metadata declares `context_size=2` and `vocab_size=500`; joiner
metadata declares `joiner_dim=320`. The empty hypothesis is `[-1, 0]`, where
token 0 is blank. The host computes log-softmax and maintains up to four active
paths by default. Blank and unknown are non-emitting tokens.

### Keyword graph and detection

Phrases are uppercased, tokenized by the generated English unigram tokenizer,
and inserted into a trie with failure and output links so overlapping phrases
work. Examples from the source SentencePiece model are:

```text
rain in Spain       -> ▁RA IN ▁IN ▁SP AIN
hey telosnex        -> ▁HE Y ▁T E LO S NE X
mainly on the plain -> ▁MA IN LY ▁ON ▁THE ▁P LA IN
```

Every emitted matching token receives the phrase's context boost. Detection
requires the best hypothesis to reach a terminal graph state, more than the
configured number of trailing blank frames (default 1), and a mean emitted-token
probability at or above the phrase threshold (default 0.25). Hypotheses reset
after detection.

## Compatibility

ONNX Runtime 1.27.0 produces incorrect encoder output on Apple SME-capable CPUs
when its KleidiAI convolution path handles the Zipformer frontend's asymmetric
padding. Inference succeeds silently but emits only blanks. FONNX therefore
sets `mlas.disable_kleidiai=1` on this encoder session. The workaround can be
removed after the Native Asset moves to ORT 1.27.1 or newer, which includes the
fix for [microsoft/onnxruntime#28571](https://github.com/microsoft/onnxruntime/issues/28571).
The end-to-end fixture must remain mandatory to catch regressions.

## Reference result

The original feasibility check used sherpa-onnx v1.10.46 as a behavioral
oracle. On an Apple M4 with two CPU threads, the three reference recordings
decoded in 66-180 ms (75-93x real time), approximately 1.1-1.3% of one CPU core
while continuously processing speech. This was not a battery benchmark and did
not include microphone capture, resampling, thread wakeups, or platform audio
policy.

## Validation

Focused tests are:

```bash
dart dev/affected_tests.dart --run lib/models/keyword_spotter
```

They cover tokenizer behavior, the overlapping context graph, streaming fbank
parity, runtime phrase replacement, transcription, session recreation, and
end-to-end detection against the checked-in example bundle. Android and iOS
also run the same fixture through the Native Assets FFI backend.

Licensing and provenance are documented in `THIRD_PARTY_NOTICES.md`; the full
Apache License 2.0 is included in this directory.
