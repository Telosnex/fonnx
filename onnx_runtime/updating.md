# Updating
1. https://onnxruntime.ai/docs/reference/releases-servicing.html
2. Download and extract ex. onnxruntime-osx-arm64-1.16.0.tgz
3. From lib folder, take dylib and dsym put in ex. macOS/onnx_runtime/osx 
- platform subfolder because ex. for macOS, podspec needs to be altered
4. From include, take headers and copy to ex. onnx_runtime/headers
5. Generate bindings: 
a. Setup LLVM, etc. See "Using this package" at https://pub.dev/packages/ffigen 
b. `dart run ffigen --config onnx_runtime/ffigen_config.yaml`
c. Done!


# Verifying

## Test
Launching the Example app and press Test Mini-lm-l6-v2. 
Then, the word "match" should display below the button.

## macOS
The binary must support both Apple Silicon and Intel. See [here](https://developer.apple.com/documentation/apple-silicon/building-a-universal-macos-binary) for detailed info from Apple. 

TL;DR:
1. Build on Apple Silicon in profile mode.
2. You can then find the .app in the build/ directory. The easiest way to locate it is to right click on the running app, hover Options, then press Show in Finder. 
3. Right click on the .app and choose Get Info. At the bottom of the General section, there is a checkbox that says Open using Rosetta. Launch the app again, and verify it works.