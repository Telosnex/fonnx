## Source
`whisper_tiny_encoder.onnx` and `whisper_tiny_decoder.onnx` are
`onnx/encoder_model.onnx` and `onnx/decoder_model_merged.onnx` of
[onnx-community/whisper-tiny](https://huggingface.co/onnx-community/whisper-tiny)
at revision `ff4177021cc41f7db950912b73ea4fdf7d01d8e7`, unchanged (fp32).
The original model is [openai/whisper-tiny](https://huggingface.co/openai/whisper-tiny).

`lib/models/whisper/src/whisper_vocabulary.dart` comes from `tokenizer.json`
and `generation_config.json` at the same revision:

```sh
dart tool/generate_whisper_vocabulary.dart tokenizer.json \
  generation_config.json \
  onnx-community/whisper-tiny@ff4177021cc41f7db950912b73ea4fdf7d01d8e7
```

Whisper base and small are not in this repo. `WhisperBundle.base` and
`WhisperBundle.small` load the same two files of
[onnx-community/whisper-base](https://huggingface.co/onnx-community/whisper-base)
at `1846881b6b3a3024392c1eea3ad983695bc23925` and
[onnx-community/whisper-small](https://huggingface.co/onnx-community/whisper-small)
at `36050c46d777d46dc4b5f43f6d90574fc38f8732`, renamed to
`whisper_<size>_encoder.onnx` and `whisper_<size>_decoder.onnx`. They have
the same `tokenizer.json` as tiny. Their `generation_config.json` differs
only in `alignment_heads`, which fonnx does not use.

## Runtime
Both graphs use only standard ONNX and ORT operators. They run on the stock
ORT native libraries and on stock ORT Web, without ORT Extensions. fonnx
computes the log-mel features, runs the beam search, and decodes the tokens
in Dart (`lib/models/whisper/src/`).

Quantized versions of these files exist in the same repository. On CPU they
were slower than fp32 and changed the transcripts (October 2026), so fonnx
uses fp32.

## Quality
whisper-tiny is included in this repo to enable automated testing.
Testing shows that whisper-tiny and whisper-base would have a bad user
experience: they clearly have issues with every test transcription.
whisper-small does not.
