## Implementing ONNX Runtime

### FFI: macOS, Windows, Linux
The ONNX C library can be used for macOS, Windows, and Linux.
Flutter can call into it via FFI.

### iOS
iOS build fails when linked against .dylib provided with ONNX releases. They are explicitly marked as for macOS. 

For iOS, we link directly against the ONNX Objective-C library. Then, call it from a Flutter plugin. A Flutter plugin bridges Dart and native code. In practice, Swift code that can be called from Dart. There is _a_ performance penalty for serialization across the bridge, but it's not substantial.

### Web
Sending these headers with the request for the ONNX JS package gives a 10x speedup:

  Cross-Origin-Embedder-Policy: require-corp
  Cross-Origin-Opener-Policy: same-origin

See [this GitHub issue](https://github.com/nagadomi/nunif/issues/34) for details. TL;DR: It allows use of multiple threads by ONNX's WASM implementation by using a SharedArrayBuffer.