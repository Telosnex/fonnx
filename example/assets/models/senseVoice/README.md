## Source
The files are on Hugging Face in
[`telosnex/fonnx`](https://huggingface.co/telosnex/fonnx), not in Git.
`dart run tool/fetch_hf_models.dart senseVoice` downloads them here, and
`ensureFonnxRuntimeModel` downloads them in an app.

`sense_voice_small_int8.onnx` and `sense_voice_small_tokens.txt` are
`model.int8.onnx` and `tokens.txt` of the sherpa-onnx archive
[`sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17.tar.bz2`](https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17.tar.bz2),
unchanged. It is
[FunAudioLLM/SenseVoiceSmall](https://huggingface.co/FunAudioLLM/SenseVoiceSmall)
by Tongyi Lab, Alibaba, under the
[FunASR Model License](https://github.com/modelscope/FunASR/blob/main/MODEL_LICENSE):
Mandarin, Cantonese, English, Japanese and Korean.

Do not use the 2025-09-09 sherpa-onnx export. It is a Cantonese fine-tune
(ASLP-lab/WSYue-ASR); it had 77% CER on FLEURS Japanese and Korean.

## Runtime
One graph with standard ONNX and ORT operators. Inputs: `x` (frames × 560
float), `x_length`, `language` and `text_norm` (int32). fonnx computes the
features (`lib/models/senseVoice/src/sense_voice_features.dart`), runs greedy
CTC with blank 0, drops the first four tokens (language, emotion, event, text
normalization), and joins the tokens. The mean and standard deviation of the
features are the `neg_mean` and `inv_stddev` metadata of this export.

## Quality
60 FLEURS test sentences per language, punctuation and case ignored
(October 2026, sherpa-onnx with the same file). Characters wrong for
Mandarin, Japanese and Korean; words wrong for English.

| | Mandarin | Japanese | Korean | English |
|---|---|---|---|---|
| SenseVoice Small | 5.5 | 6.4 | 7.7 | 7.0 |
| Whisper Small | 9.8 | 12.3 | 8.9 | 6.2 |
| Whisper Tiny | 25.6 | 39.4 | 21.7 | 11.9 |

Audio without speech often gives a short false transcript, such as "그.".
Run a voice activity detector first.
