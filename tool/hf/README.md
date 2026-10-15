---
license: other
license_name: per-file
tags:
- onnx
---

# fonnx models

ONNX models for [fonnx](https://github.com/Telosnex/fonnx), which runs ONNX
models in Flutter on every platform.

fonnx pins each file by the commit of this repository and its SHA-256 (see
`native_artifacts/manifest.json` in fonnx). Do not squash the history of this
repository or delete files from it: shipped apps download files by commit.

Each file has the license of its source model.

## Files that fonnx pins

| File | Source | License |
|---|---|---|
| `decoder-epoch-12-avg-2-chunk-16-left-64.int8.onnx`, `encoder-…`, `joiner-…` | [sherpa-onnx keyword spotter](https://github.com/k2-fsa/sherpa-onnx/releases/tag/kws-models), GigaSpeech Zipformer 3M | Apache-2.0 |
| `fastconformer_ctc_multilingual_int8.onnx` | [NVIDIA stt_multilingual_fastconformer_hybrid_large_pc](https://catalog.ngc.nvidia.com/orgs/nvidia/teams/nemo/models/stt_multilingual_fastconformer_hybrid_large_pc), CTC branch, int8 export of [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx/releases/tag/asr-models) | CC-BY-4.0 |
| `futo_swipe_*.onnx` | Derived from FUTO Swipe (see below) | FUTO Model Weights License 1.0 |
| `kokoro_prosody.onnx`, `kokoro_decoder.onnx` | [hexgrad/Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M) v1.0, uint8 export of [onnx-community/Kokoro-82M-v1.0-ONNX](https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX) at `1939ad2a8e416c0acfeecc08a694d14ef25f2231`, split in two by fonnx | Apache-2.0 |
| `kokoro_voice_*.bin` | The 28 English voices of the same onnx-community revision, unchanged | Apache-2.0 |
| `kokoro_misaki_{us,gb}_{gold,silver}.json` | Pronunciation dictionaries of [hexgrad/misaki](https://github.com/hexgrad/misaki) 0.9.4, unchanged | Apache-2.0 |
| `kokoro_g2p_fallback_en_us.onnx`, `….json` | [PeterReid/graphemes_to_phonemes_en_us](https://huggingface.co/PeterReid/graphemes_to_phonemes_en_us) at `a5631b285d18d59483c32c0c3379cb9fac924f4b`, ONNX export by fonnx | Apache-2.0 |
| `kokoro_spacy_en_core_web_sm.json`, `…_tagger.bin` | [spaCy en_core_web_sm](https://github.com/explosion/spacy-models) 3.8.0, tokenizer rules and tagger weights converted by fonnx | MIT |
| `magika.onnx` | [Google Magika](https://github.com/google/magika) | Apache-2.0 |
| `miniLmL6V2.onnx` | [sentence-transformers/all-MiniLM-L6-v2](https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2) | Apache-2.0 |
| `msmarcoMiniLmL6V3.onnx` | [sentence-transformers/msmarco-MiniLM-L-6-v3](https://huggingface.co/sentence-transformers/msmarco-MiniLM-L-6-v3) | Apache-2.0 |
| `parakeet_tdt_v3_decoder_int8.onnx`, `…_encoder_…`, `…_joiner_…` | [nvidia/parakeet-tdt-0.6b-v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3), int8 export of [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx/releases/tag/asr-models) | CC-BY-4.0 |
| `potion8m.onnx`, `potion32m.onnx` | [Minish Lab](https://huggingface.co/minishlab) potion-base-8M and potion-base-32M | MIT |
| `pyannote_seg3.onnx` | [pyannote/segmentation-3.0](https://huggingface.co/pyannote/segmentation-3.0) | MIT |
| `sense_voice_small_int8.onnx`, `sense_voice_small_tokens.txt` | [FunAudioLLM/SenseVoiceSmall](https://huggingface.co/FunAudioLLM/SenseVoiceSmall) (Alibaba), int8 export of [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx/releases/tag/asr-models) (2024-07-17) | [FunASR Model License](https://github.com/modelscope/FunASR/blob/main/MODEL_LICENSE) |
| `silero_vad_v6.2.1.onnx` | [Silero VAD v6.2.1](https://github.com/snakers4/silero-vad/releases/tag/v6.2.1) | MIT |
| `whisper_tiny_decoder.onnx`, `whisper_tiny_encoder.onnx` | [onnx-community/whisper-tiny](https://huggingface.co/onnx-community/whisper-tiny), from [openai/whisper-tiny](https://huggingface.co/openai/whisper-tiny) | MIT |

## Other files

`whisper_{base,small}_{encoder,decoder}.onnx` are from
[onnx-community/whisper-base](https://huggingface.co/onnx-community/whisper-base)
and [onnx-community/whisper-small](https://huggingface.co/onnx-community/whisper-small)
(MIT). `bpe_decoder.onnx`, `silero_vad.onnx`, `whisper_{tiny,base,small}.onnx`
and `whisper_v3_turbo_olive.onnx` are files of earlier fonnx versions.

## Attribution

The NeMo ASR files are exports of NVIDIA models, used under
[CC-BY-4.0](https://creativecommons.org/licenses/by/4.0/). fonnx did not
change the files of the sherpa-onnx exports.

The Kokoro files are from Kokoro-82M by hexgrad, used under Apache-2.0.
fonnx split the onnx-community export into a prosody model and a decoder
model; the weights are unchanged. The misaki dictionaries, the fallback
model and the spaCy data are used under their licenses above.

The SenseVoice files are the sherpa-onnx export of SenseVoice Small by
Tongyi Lab, Alibaba, unchanged, used under the FunASR Model License.

The `futo_swipe_*.onnx` files are derived from FUTO Swipe and are subject to
the FUTO Model Weights License 1.0. `LICENSE-FUTO.txt` in this repository has
the complete, unchanged terms. They are an unofficial ONNX conversion; this
does not imply sponsorship, affiliation, or endorsement by FUTO. No training or
intentional weight changes were made. A product that uses them must show its
users that it is powered by "FUTO Swipe" technology.
