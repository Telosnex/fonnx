<img src="header.png"
     alt="FONNX image header, bird like Flutter mascot DJing. Text reads: FONNX. Any model
on any edge. Run ONNX model & runtime, with platform-specific acceleration,  inside Flutter, a modern, beautiful, cross-platform development
framework."
     style="float: left; margin-right: 0px;" />

# FONNX
## Any model on any edge
Run ONNX model & runtime, with platform-specific acceleration, inside Flutter, a modern, beautiful, cross-platform development framework.

## What is FONNX?
FONNX is a Flutter plugin that allows you to run ONNX models via the ONNX runtime inside a Flutter app. 
Flutter supports iOS, Android, Web, Linux, Windows, and macOS. 
FONNX supports _all_ of these platforms.
It is a wrapper around the [ONNX runtime](https://onnxruntime.ai/), designed for optimal performance.
It leverages native acceleration capabilities, from CoreML on iOS, to Android Neural Networks API on Android, to WASM SIMD on Web.
The ONNX runtime runs models in the ONNX format, which supports a wide variety of models, including Pytorch, Tensorflow, and more.

## Converting models to ONNX runtime format
A command-line tool called `optimum-cli` from HuggingFace converts Pytorch and Tensorflow models to ONNX. 
This covers the vast majority of models.

See [official documentation](https://huggingface.co/docs/optimum/exporters/onnx/usage_guides/export_a_model) or the 
quick start [snippet on GitHub](https://github.com/huggingface/optimum#run-the-exported-model-using-onnx-runtime).
`optimum-cli` supports quantization as well, which can significantly reduce model size with negligible impact on accuracy.

Another tool that automates conversion to ONNX is [HFOnnx](https://neuml.github.io/txtai/pipeline/train/hfonnx/).
It exported the MiniLM-L6-V2 model used in the example app.
At 22 MB, it improved upon the 66 MB `optimum-cli` quantized version, 90 MB unquantized. 
The original Pytorch model was 90 MB.

- Brief intro on how ONNX model format & runtime work [huggingface.com](https://huggingface.co/docs/optimum/onnxruntime/concept_guides/onnx)
- [Netron](https://netron.app/) allows you to view ONNX models, inspect their runtime graph, and export them to other formats
- [ONNX](https://onnx.ai/) is a model format that allows you to run models on any platform

## Models
### MiniLM-L6-V2
The example app uses the MiniLM-L6-V2 model, a small, fast, and accurate language model.
It can generate embeddings for text, which can be used for semantic search, clustering, and more.
This forms the basis of a vector database: a vector for a chunk of text from a document.
Running the model locally provides significant privacy benefits, as well as latency benefits.
The speed of running the model locally is significantly faster than the speed of a network request to a server. (60 ms vs. 500 ms)


#### Benefits
Semantic search is like magic. 
It allows you to find documents that are similar to a query, even if they don't contain the query.
For example, 

#### Benchmarks
- iPhone 14: 67 ms
- Pixel Fold: 33 ms
- WASM-SIMD: 41 ms
- macOS: 13 ms
Average time to perform 1 embedding, which represents 1 page of double-spaced text.

Run on Thurs Oct 12th 2023.
macOS and WASM-SIMD on MacBook Pro M2 Max.
Average of 100 embeddings, after a warmup of 10.
Mix of lorem ipsum text from 8 languages.


The MiniLM-L6-V2 model is 22 MB, and runs in 20 ms on an iPhone 12 Pro Max.
