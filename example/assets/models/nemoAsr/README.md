## Source
The models are on Hugging Face in
[`telosnex/fonnx`](https://huggingface.co/telosnex/fonnx), not in Git.
`dart run tool/fetch_hf_models.dart nemoAsr` downloads them here, and
`ensureFonnxRuntimeModel` downloads them in an app.

`fastconformer_ctc_multilingual_int8.onnx` is `model.int8.onnx` of the
sherpa-onnx archive
[`sherpa-onnx-nemo-fast-conformer-ctc-be-de-en-es-fr-hr-it-pl-ru-uk-20k-int8.tar.bz2`](https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-nemo-fast-conformer-ctc-be-de-en-es-fr-hr-it-pl-ru-uk-20k-int8.tar.bz2),
unchanged (SHA-256 `e3ea888bcc90cafdeeedeea26f6e8ca2186d8af7939236e0eb246206f5098c00`).
It is the CTC branch of NVIDIA's
[stt_multilingual_fastconformer_hybrid_large_pc](https://catalog.ngc.nvidia.com/orgs/nvidia/teams/nemo/models/stt_multilingual_fastconformer_hybrid_large_pc)
(114M parameters, CC-BY-4.0): Belarusian, Croatian, English, French, German,
Italian, Polish, Russian, Spanish and Ukrainian.

`NemoAsrBundle.parakeetTdtV3` loads
`encoder.int8.onnx`, `decoder.int8.onnx` and `joiner.int8.onnx` of
[`sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8.tar.bz2`](https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8.tar.bz2),
renamed to `parakeet_tdt_v3_<part>_int8.onnx`. The original model is
[nvidia/parakeet-tdt-0.6b-v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3)
(CC-BY-4.0): English and 24 other European languages.

| File | SHA-256 | Bytes |
|---|---|---|
| `parakeet_tdt_v3_encoder_int8.onnx` | `acfc2b4456377e15d04f0243af540b7fe7c992f8d898d751cf134c3a55fd2247` | 652184281 |
| `parakeet_tdt_v3_decoder_int8.onnx` | `179e50c43d1a9de79c8a24149a2f9bac6eb5981823f2a2ed88d655b24248db4e` | 11845275 |
| `parakeet_tdt_v3_joiner_int8.onnx` | `3164c13fc2821009440d20fcb5fdc78bff28b4db2f8d0f0b329101719c0948b3` | 6355277 |

`lib/models/nemoAsr/src/nemo_asr_vocabulary.dart` comes from the
`tokens.txt` of the two archives:

```sh
dart tool/generate_nemo_asr_vocabulary.dart <ctc tokens.txt> <v3 tokens.txt>
```

## Runtime
The graphs use only standard ONNX and ORT operators, on stock ORT native and
ORT Web. fonnx computes the log-mel features (NeMo's preprocessor: 80 mel bins
for CTC, 128 for v3), runs greedy CTC or TDT decoding, and decodes the tokens
in Dart (`lib/models/nemoAsr/src/`). The decoding rules are those of
sherpa-onnx.

## Quality
Word error rate on 60 FLEURS test sentences per language, punctuation and
case ignored (October 2026, sherpa-onnx with the same files):

| | en | de | fr | es | it | pl |
|---|---|---|---|---|---|---|
| Whisper tiny | 11.9 | 29.3 | 46.8 | 19.0 | 30.7 | 53.0 |
| FastConformer CTC | 9.4 | 7.2 | 14.6 | 6.4 | 5.9 | 12.9 |
| Whisper small | 6.2 | 9.7 | 14.9 | 5.6 | 8.0 | 15.7 |
| Parakeet TDT v3 | 7.3 | 5.5 | 9.7 | 4.1 | 4.2 | 11.3 |

Both models lose words when speech starts at the first sample. fonnx adds up
to 250 ms of silence before such audio, and runs v3 again with 500 ms more if
it gives no tokens.
