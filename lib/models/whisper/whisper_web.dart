import 'dart:typed_data';
import 'package:js/js.dart';
import 'package:js/js_util.dart';

import 'package:fonnx/models/whisper/whisper.dart';

Whisper getWhisper(String path) => WhisperWeb(path);

@JS()
class Promise<T> {
  external Promise(
      void Function(void Function(T result) resolve, Function reject) executor);
  external Promise then(void Function(T result) onFulfilled,
      [Function onRejected]);
}

@JS('window.whisper')
external Promise<String> whisperJs(String modelPath, List<int> audioBytes);

class WhisperWeb implements Whisper {
  @override
  final String modelPath;

  WhisperWeb(this.modelPath);

  @override
  Future<String> doInference(Uint8List bytes) async {
    final jsObject = await promiseToFuture(whisperJs(modelPath, bytes));

    if (jsObject == null) {
      throw Exception('Whisper transcription returned from JS code is null');
    }

    if (jsObject is! String) {
      throw Exception(
          'Whisper transcription returned from JS code is not a string, it is a ${jsObject.runtimeType}');
    }

    return jsObject;
  }
}
