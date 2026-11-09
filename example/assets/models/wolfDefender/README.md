## Source
The files are on Hugging Face in
[`telosnex/fonnx`](https://huggingface.co/telosnex/fonnx), not in Git.
`dart run tool/fetch_hf_models.dart wolfDefender` downloads them here, and
`ensureFonnxRuntimeModel` downloads them in an app.

They are Wolf Defender Edge by Patronus,
[`patronus-studio/wolf-defender-prompt-injection-edge`](https://huggingface.co/patronus-studio/wolf-defender-prompt-injection-edge)
at revision `a65713895aafa398e71f151f50d33449b477b4c9`, under Apache-2.0
(`lib/models/wolfDefender/LICENSE-APACHE-2.0`):

| fonnx file | Patronus file | SHA-256 |
|---|---|---|
| `wolf_defender_edge_int8_weights.onnx` | `onnx/int8_int4_embeddings_x86_weight_only/model.onnx`, unchanged | `a27a07ff…b013` |
| `wolf_defender_edge_tokenizer.bin` | `tokenizer.json` (`17e323fc…f0a6`), converted | `c8ad6619…6aa7` |

To make the tokenizer file:

```bash
dart run tool/wolf_defender/convert_tokenizer.dart tokenizer.json \
  example/assets/models/wolfDefender/wolf_defender_edge_tokenizer.bin
```

## Runtime
A ModernBERT sequence classifier: inputs `input_ids` and `attention_mask`
(int64, 1 × at most 2048), output `logits` (benign, injection). fonnx
tokenizes in Dart (`src/wolf_defender_tokenizer.dart`), adds `<bos>` (2) and
`<eos>` (1) to each window of 2046 tokens, and pools the windows as
Patronus's `inference.py` and `POOLING.json` define: a per-class smooth
maximum with temperature 1 for one window and 0.1 for more, then softmax.
The threshold is a probability greater than 0.5.

Because the maximum is per class, a strongly benign window and a strongly
injected window of the same text can balance near 0.5.

## Choice of file
Patronus publishes fp32 (320 MB), fp16 (160 MB), mixed (130 MB) and two
58 MB files with int8 weights and an int4 embedding table. One has dynamic
int8 activations; the other, `x86_weight_only`, float activations. Despite
its name, the second is the one that is accurate on every CPU. Decisions
that matched fp32 on 691 texts (the deepset/prompt-injections splits and the
fonnx goldens), ORT 1.31.1, November 2026:

| | Apple M4 Max | x86-64 (Linux, Docker) | WebAssembly (ORT Web) |
|---|---|---|---|
| dynamic int8 activations | 98.7% | 94.4% | 94.1% |
| weight-only (`wolf_defender_edge_int8_weights.onnx`) | 99.1% | 99.0% | 99.0% |

On the GitHub Actions ARM runners (Linux, Windows and macOS), the dynamic
file gave 0.01 for a reference text that fp32 and Apple M4 put at 0.96.
After loading, the dynamic file needs about 120 MB and the weight-only file
about 200 MB.

## Goldens
`test/data/wolf_defender/` has Hugging Face `tokenizers` IDs for 157 texts,
and the probabilities of Patronus's `inference.py` (the weight-only file, and fp32) for 28 texts, from
`tool/wolf_defender/make_goldens.py`.
