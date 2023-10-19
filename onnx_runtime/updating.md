# Updating ONNX Runtime
1. 
For macOS/Linux/Windows:
- Find latest release on [Github](https://github.com/microsoft/onnxruntime/releases). 
[Official ONNX page][https://onnxruntime.ai/docs/reference/releases-servicing.html] is behind but has more info.
For iOS:
- Use latest pod.
2. Download and extract ex. onnxruntime-osx-arm64-1.16.0.tgz
3. From lib folder, take dylib and dsym put in ex. macOS/onnx_runtime/osx 
- platform subfolder because ex. for macOS, podspec needs to be altered
4. From include, take headers and copy to ex. onnx_runtime/headers
5. Generate bindings: 
a. Setup LLVM, etc. See "Using this package" at https://pub.dev/packages/ffigen 
b. `dart run ffigen --config onnx_runtime/ffigen_config.yaml`
c. Done!

## Verifying

### Test
Launching the Example app and press Test Mini-lm-l6-v2. 
Then, the word "match" should display below the button.

### macOS
The binary must support both Apple Silicon and Intel. See [here](https://developer.apple.com/documentation/apple-silicon/building-a-universal-macos-binary) for detailed info from Apple. 

TL;DR:
1. Build on Apple Silicon in profile mode.
2. You can then find the .app in the build/ directory. The easiest way to locate it is to right click on the running app, hover Options, then press Show in Finder. 
3. Right click on the .app and choose Get Info. At the bottom of the General section, there is a checkbox that says Open using Rosetta. Launch the app again, and verify it works.

### Windows
Windows x64 is all we need to support currently.
Flutter is not quite stable for Windows arm64 ([Github issue](https://github.com/flutter/flutter/issues/62597)).
Neither arm nor arm64 devices are particularly numerous.
As of October 2023, at most ~0.35% of Windows devices could plausibly be Win32. [source](https://www.pcbenchmarks.net/os-marketshare.html)

# Updating ONNX Runtime Extensions
ONNX Runtime Extensions is a supplementary library that includes everything from audio decoding to a BPE tokenizer: this enables Olive, a more intense ONNX optimizer, to do things such as export a Whisper model that combines the encoder and decoder model, takes audio bytes as input, and provides strings as output: this is _much_ more convenient and presumably faster.

It is also _significantly_ harder to land. 

For desktop platforms, you need to checkout [the Github repo](https://github.com/microsoft/onnxruntime-extensions) and build on the platform you're producing. For example, on Linux, I ran `./build.sh` in the checkout root, then copied `/GitHub/onnxruntime-extensions/out/Linux/RelWithDebInfo/lib/libortextensions.so.0.10.0` to `/Github/fonnx/linux/onnx_runtime/libortextensions.so.0.9.0`.

The version naming difference is because the repo labels with the next version, but it makes more sense to couple it to the current release, so it's easier to understand if iOS/Android are on the same version.

iOS and Android require importing a package, see [here on onnxruntime.ai](https://onnxruntime.ai/docs/extensions/).
