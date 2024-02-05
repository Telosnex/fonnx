import 'package:fonnx/models/whisper/whisper.dart';
import 'package:js/js.dart';
import 'package:js/js_util.dart';

Whisper getWhisper(String path) => WhisperWeb(path);

@JS()
class Promise<T> {
  external Promise(
      void Function(void Function(T result) resolve, Function reject) executor);
  external Promise then(void Function(T result) onFulfilled,
      [Function onRejected]);
}

@JS('window.whisper')
external Promise<List<List<double>>> whisperJs(
    String modelPath, List<int> wordpieces);

class WhisperWeb implements Whisper {
  @override
  final String modelPath;

  WhisperWeb(this.modelPath);

  @override
  Future<String> doInference(List<int> audioBytes) async {
    final jsObject = await promiseToFuture(whisperJs(modelPath, audioBytes));

    if (jsObject == null) {
      throw Exception('Inference returned from JS code is null');
    }

    final jsList = (jsObject as List<dynamic>);
    final result = jsList.cast<String>().join(' ');
    return result;
  }
}
