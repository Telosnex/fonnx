import 'dart:js_interop';
import 'dart:typed_data';

import 'package:fonnx/models/whisper/whisper.dart';

Whisper getWhisper(String path) => WhisperWeb(path);

@JS('window.whisper')
external JSPromise<JSString?> whisperJs(String modelPath, JSUint8Array audioBytes);

class WhisperWeb implements Whisper {
  @override
  final String modelPath;

  WhisperWeb(this.modelPath);

  @override
  Future<String> doInference(Uint8List bytes) async {
    final jsObject = await whisperJs(modelPath, bytes.toJS).toDart;
    final text = jsObject?.toDart;
    if (text == null) {
      throw Exception('Whisper transcription returned from JS code is null');
    }
    return text;
  }
}
