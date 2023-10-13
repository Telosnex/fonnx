<img src="header.png"
     alt="FONNX image header, bird like Flutter mascot DJing. Text reads: FONNX. Any model
on any edge. Run ONNX model & runtime, with platform-specific acceleration,  inside Flutter, a modern, beautiful, cross-platform development
framework."
     style="float: left; margin-right: 0px;" />

# FONNX
## Any model on any edge
Run ML models natively on any platform. ONNX models can be run on iOS, Android, Web, Linux, Windows, and macOS.

## What is FONNX?
FONNX is a Flutter library for running ONNX models.
Flutter, and FONNX, run natively on iOS, Android, Web, Linux, Windows, and macOS. 
FONNX leverages ONNX to provide native acceleration capabilities, from CoreML on iOS, to Android Neural Networks API on Android, to WASM SIMD on Web.
A wide variety of models can be easily converted to ONNX format, including modesl from Pytorch, Tensorflow, and more.

## Getting ONNX Models
### HuggingFace
[HuggingFace](https://huggingface.co/models) has a large collection of models, including many that are ONNX format. 90% of the models are Pytorch, which can be converted to ONNX.

Here is a search for [ONNX models](https://huggingface.co/models?sort=trending&search=onnx). 

### Export ONNX from Pytorch, Tensorflow, & more
A command-line tool called `optimum-cli` from HuggingFace converts Pytorch and Tensorflow models. This covers the vast majority of models. `optimum-cli` can also quantize models, significantly reduce model size, usually with negligible impact on accuracy.

See [official documentation](https://huggingface.co/docs/optimum/exporters/onnx/usage_guides/export_a_model) or the 
quick start [snippet on GitHub](https://github.com/huggingface/optimum#run-the-exported-model-using-onnx-runtime).  
Another tool that automates conversion to ONNX is [HFOnnx](https://neuml.github.io/txtai/pipeline/train/hfonnx/).

- Brief intro on how ONNX model format & runtime work [huggingface.com](https://huggingface.co/docs/optimum/onnxruntime/concept_guides/onnx)
- [Netron](https://netron.app/) allows you to view ONNX models, inspect their runtime graph, and export them to other formats
- [ONNX](https://onnx.ai/) is a model format that allows you to run models on any platform

## Models
### MiniLM-L6-V2
The example app uses the MiniLM-L6-V2 model, a small, fast, and accurate language model.  

It can generate embeddings for text, which can be used for semantic search, clustering, and more.  

This forms the basis of a vector database: a vector for a chunk of text from a document. Many popular vector databases are built on top of MiniLM.

Running the model locally provides significant privacy benefits, as well as latency benefits.  

It allows knowledge to be stored locally, without having to be stored on a server for eventual retrieval.

The speed of running the model locally is significantly faster than the speed of a network request to a server. (60 ms vs. 500 ms)  

The model came from [HuggingFace](https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2). and was converted to ONNX format using [HFOnnx](https://neuml.github.io/txtai/pipeline/train/hfonnx/)
At 22 MB, it improved on `optimum-cli`'s 66 MB. The original Pytorch model was 90 MB.


#### Benefits
Semantic search allows you to find documents that are similar to a query, even if they don't contain the query.
For example, "whats my jewelry pin" and "my safe passcode is 1234" has a high similarity score, almost as much 
as "weather forecast" and 'WeatherChannel Spain: the weather is sunny and warm'.

MiniLM-V6-V2 is a product of the sentence-transformers library, which is a great resource for semantic search and clustering.
- [https://www.sbert.net/examples/applications/semantic-search/README.html](https://www.sbert.net/examples/applications/semantic-search/README.html)


#### Benchmarks
**iPhone 14**: 67 ms  
**Pixel Fold**: 33 ms  
**macOS**: 13 ms  
**WASM SIMD**: 41 ms  

Avg. ms for 1 embedding / 200 words.

* Run on Thurs Oct 12th 2023.  
* macOS and WASM-SIMD on MacBook Pro M2 Max.  
* Average of 100 embeddings, after a warmup of 10.  
* Input is Mix of lorem ipsum text from 8 languages.  

