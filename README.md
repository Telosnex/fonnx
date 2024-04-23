<img src="header.png"
     alt="FONNX image header, bird like Flutter mascot DJing. Text reads: FONNX. Any model
on any edge. Run ONNX model & runtime, with platform-specific acceleration,  inside Flutter, a modern, beautiful, cross-platform development
framework."
     style="float: left; margin-right: 0px;" />
| Platform     | Status |
|--------------|--------|
| __Android__  | [![Codemagic build status](https://api.codemagic.io/apps/652897766ee3f7af8490a79f/android-build/status_badge.svg)](https://codemagic.io/app/652897766ee3f7af8490a79f/android-build/latest_build) |
| __iOS__  | [![Codemagic build status](https://api.codemagic.io/apps/652897766ee3f7af8490a79f/ios-build/status_badge.svg)](https://codemagic.io/app/652897766ee3f7af8490a79f/ios-build/latest_build) |
| __Linux__    | [![Codemagic build status](https://api.codemagic.io/apps/652897766ee3f7af8490a79f/linux-build/status_badge.svg)](https://codemagic.io/app/652897766ee3f7af8490a79f/linux-build/latest_build) |
| __macOS__ | [![Codemagic build status](https://api.codemagic.io/apps/652897766ee3f7af8490a79f/macos-build/status_badge.svg)](https://codemagic.io/app/652897766ee3f7af8490a79f/macos-build/latest_build) |
| __Web__  | [![Codemagic build status](https://api.codemagic.io/apps/652897766ee3f7af8490a79f/web-build/status_badge.svg)](https://codemagic.io/app/652897766ee3f7af8490a79f/web-build/latest_build) |
| __Windows__  | [![Codemagic build status](https://api.codemagic.io/apps/652897766ee3f7af8490a79f/windows-build/status_badge.svg)](https://codemagic.io/app/652897766ee3f7af8490a79f/windows-build/latest_build) |

# Changelog

## 2024 Feb 13

- Whisper now supported on all platforms besides web.
- Whisper models support timestamps. (not exposed via API, yet)
- Silero VAD added to all platforms besides web.
- Silero VAD enables detecting when the user is done speaking with a much higher success rate than relying on volume levels.
- Example contains `SttService`, an example of how to integrate the VAD and Whisper together with an easy to use interface. (Stream<String>)

# FONNX

## Any model on any edge

Run ML models natively on any platform. ONNX models can be run on iOS, Android, Web, Linux, Windows, and macOS.

## What is FONNX?

FONNX is a Flutter library for running ONNX models.
Flutter, and FONNX, run natively on iOS, Android, Web, Linux, Windows, and macOS.
FONNX leverages [ONNX](https://onnx.ai/) to provide native acceleration capabilities, from CoreML on iOS, to Android Neural Networks API on Android, to WASM SIMD on Web.
Most models can be easily converted to ONNX format, including models from Pytorch, Tensorflow, and more.

## Getting ONNX Models

### Hugging Face

[🤗 Hugging Face](https://huggingface.co/models) has a large collection of models, including many that are ONNX format. 90% of the models are Pytorch, which can be converted to ONNX.

Here is a search for [ONNX models](https://huggingface.co/models?sort=trending&search=onnx).

### Export ONNX from Pytorch, Tensorflow, & more

A command-line tool called `optimum-cli` from HuggingFace converts Pytorch and Tensorflow models. This covers the vast majority of models. `optimum-cli` can also quantize models, significantly reduce model size, usually with negligible impact on accuracy.

See [official documentation](https://huggingface.co/docs/optimum/exporters/onnx/usage_guides/export_a_model) or the
quick start [snippet on GitHub](https://github.com/huggingface/optimum#run-the-exported-model-using-onnx-runtime).  
Another tool that automates conversion to ONNX is [HFOnnx](https://neuml.github.io/txtai/pipeline/train/hfonnx/). It was used to export the text embeddings models in this repo. Its advantages included a significantly smaller model size, and incorporating post-processing (pooling) into the model itself.

- Brief intro to how ONNX model format & runtime work [huggingface.com](https://huggingface.co/docs/optimum/onnxruntime/concept_guides/onnx)
- [Netron](https://netron.app/) allows you to view ONNX models, inspect their runtime graph, and export them to other formats

### Text Embeddings

These models generate embeddings for text.
An embedding is a vector of floating point numbers that represents the meaning of the text.  
Embeddings are the foundation of a vector database, as well as retrieval augmented generation - deciding which text snippets to provide in the limited context window of an LLM like GPT.

Running locally using FONNX provides significant privacy benefits, as well as latency benefits.
For example, rather than having to store the embedding and text of each chunk of a document on a server, they can be stored on-device.
Both MiniLM L6 V2 and MSMARCO MiniLM L6 V3 are both the product of the Sentence Transformers project. Their website has excellent documentation explaining, for instance, [semantic search](https://www.sbert.net/examples/applications/semantic-search/README.html)

#### MiniLM L6 V2

Trained on a billion sentence pairs from diverse sources, from Reddit to WikiAnswers to StackExchange.
MiniLM L6 V2 is well-suited for numerous tasks, from text classification to semantic search.
It is optimized for [symmetric search](https://www.sbert.net/examples/applications/semantic-search/README.html#symmetric-vs-asymmetric-semantic-search), where text is roughly of the same length and meaning.
Input text is divided into approximately 200 words, and an embedding is generated for each.  
[🤗 Hugging Face](https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2)

#### MSMARCO MiniLM L6 V3

Trained on pairs of Bing search queries to web pages that contained answers for the query.
It is optimized for [asymmetric semantic search](https://www.sbert.net/examples/applications/semantic-search/README.html#symmetric-vs-asymmetric-semantic-search), matching a search query to an answer.
Additionally, it has 2x the input size of MiniLM L6 V2: it can accept up to 400 words as input for one embedding.  
[🤗 Hugging Face](https://huggingface.co/sentence-transformers/msmarco-MiniLM-L-6-v3/tree/main)

#### Benchmarks

**iPhone 14**: 67 ms  
**Pixel Fold**: 33 ms  
**macOS**: 13 ms  
**WASM SIMD**: 41 ms

Avg. ms for 1 Mini LM L6 V2 embedding / 200 words.

- Run on Thurs Oct 12th 2023.
- macOS and WASM-SIMD runs on MacBook Pro M2 Max.
- Average of 100 embeddings, after a warmup of 10.
- Input is mix of lorem ipsum text from 8 languages.

# Integrating FONNX

## macOS, Windows, Linux via FFI

The ONNX C library is used for macOS, Windows, and Linux.
Flutter can call into it via FFI. Nothing special is required to use FFI on these platforms.

## iOS via ONNX pods

iOS uses the official ONNX Objective-C library. No additional tasks besides adding FONNX to your Flutter project are required.

iOS build fails when linked against .dylib provided with ONNX releases. They are explicitly marked as for macOS.

## Android via ONNX AAR

Android uses the official ONNX Android dependencies from a Maven repository. Note that ProGuard rules are required to prevent the ONNX library from being stripped.

## Web

Sending these headers with the request for the ONNX JS package gives a 10x speedup:

```
Cross-Origin-Embedder-Policy: require-corp
Cross-Origin-Opener-Policy: same-origin
```

See [this GitHub issue](https://github.com/nagadomi/nunif/issues/34) for details. TL;DR: It allows use of multiple threads by ONNX's WASM implementation by using a SharedArrayBuffer.

### Developing with Web

While developing, two issues prevent it work working on the web.
Both have workarounds

#### WASM Mime Type

You may see errors in console logs about the MIME type of the
.wasm being incorrect and starting with the wrong bytes.

That is due to local Flutter serving of the web app.

To fix, download the WASM files from the same CDN folder that hosts ort.min.js
(see _\_worker.js) and also in _\_minilm_worker.js, remove the // in front of ort.env.wasm.wasmPaths = "".

Then, place the WASM files downloaded from the CDN next to index.html.

In release mode and deployed, this is not an issue, you do not need to host the WASM files.

#### Cross-Origin-Embedder-Policy

To safely use SharedArrayBuffer, the server must send the Cross-Origin-Embedder-Policy header with the value require-corp.

See here for how to workaround it: https://github.com/nagadomi/nunif/issues/34

Note that the extension became adware, you should have Chrome set up its
permissions such that it isn't run until you click it. Also, note that you have to do
that each time the Flutter web app in debug mode's port changes.

# License

FONNX is licensed under a dual-license model.

The code as-is on GitHub is licensed under GPL v2. That requires distribution of the integrating app's source code, and this is unlikely to be desirable for commercial entities. See LICENSE.md.

Commercial licenses are also available. Contact info@telosnex.com. Expect very fair terms: our intent is to charge only entities, with a launched app, making a lot of money, with FONNX as a core dependency. The base agreement is here: https://github.com/lawndoc/dual-license-templates/blob/main/pdf/Basic-Yearly.pdf
