import 'dart:js_interop';
import 'dart:typed_data';

import 'package:fonnx/models/whisper/whisper.dart';
import 'package:fonnx/src/web_loader.dart';

Whisper getWhisper(String path) => WhisperWeb(path);

@JS('window.whisper')
external JSPromise<JSString?> whisperJs(
  String modelPath,
  JSUint8Array audioBytes,
);

class WhisperWeb implements Whisper {
  @override
  final String modelPath;

  WhisperWeb(this.modelPath);

  @override
  Future<String> doInference(Uint8List bytes) async {
    final snapshot = Uint8List.fromList(bytes);
    await loadFonnxWebModule('whisper_init.js');
    final jsObject = await whisperJs(modelPath, snapshot.toJS).toDart;
    final text = jsObject?.toDart;
    if (text == null) {
      throw Exception('Whisper transcription returned from JS code is null');
    }
    return text;
  }
}
