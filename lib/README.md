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

#### Developing with Web
While developing, two issues prevent it work working on the web.
Both have workarounds

##### WASM Mime Type
You may see errors in console logs about the MIME type of the
.wasm being incorrect and starting with the wrong bytes. 

That is due to local Flutter serving of the web app.

To fix, download the WASM files from the same CDN folder that hosts ort.min.js
(see worker.js) and also in worker.js, remove the // in front of ort.env.wasm.wasmPaths = "". 

Then, place the WASM files downloaded from the CDN next to index.html.

In release mode and deployed, this is not an issue, you do not need to host the WASM files.

##### Cross-Origin-Embedder-Policy
To safely use SharedArrayBuffer, the server must send the Cross-Origin-Embedder-Policy header with the value require-corp.

See here for how to workaround it: https://github.com/nagadomi/nunif/issues/34

Note that the extension became adware, you should have Chrome set up its
permissions such that it isn't run until you click it. Also, note that you have to do
that each time the Flutter web app in debug mode's port changes.
