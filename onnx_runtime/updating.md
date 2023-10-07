1. https://onnxruntime.ai/docs/reference/releases-servicing.html
2. Download and extract ex. onnxruntime-osx-arm64-1.16.0.tgz
3. From lib folder, take dylib and dsym put in ex. macOS/onnx_runtime/osx_arm64 
- platform subfolder because ex. for macOS, podspec needs to be altered
4. From include, take headers and copy to ex. onnx_runtime/headers
5. Generate bindings: 
a. Setup LLVM, etc. See "Using this package" at https://pub.dev/packages/ffigen 
b. `dart run ffigen --config onnx_runtime/ffigen_config.yaml`
c. Done!