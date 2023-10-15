## Original model  
https://huggingface.co/collections/openai/whisper-release-6501bba2cf999715fd953013

## Creating ONNX Model
Created optimized models using Olive, following [these instructions](https://github.com/microsoft/Olive/tree/main/examples/whisper#whisper-optimization-using-ort-toolchain). Models larger than whisper-small, i.e. whisper-medium, whisper-large, whisper-large-v2, all fail with an error about invalid protobuf (as of 2023 10 15).

## Platforms
Only macOS ARM is currently supported.
To deliver cross-platform support, the [ONNX runtime extensions](https://github.com/microsoft/onnxruntime-extensions) library needs to be compiled into binaries for macOS Intel, Linux, and Windows. Additionally, iOS and Android will need to take a dependency on the corresponding CocoaPod/Android package.

## Quality and downloading models
whisper-tiny is included in this repo to enable automated testing.
Larger models are available [in a repo on Telosnex's HuggingFace profile](https://huggingface.co/telosnex/fonnx/tree/main).
Testing shows that whisper-tiny and whisper-base would have a bad user experience,
they clearly have issues with every test transcription. whisper-small does not.