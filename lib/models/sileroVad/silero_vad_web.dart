import 'dart:convert';
import 'dart:typed_data';
import 'package:js/js.dart';
import 'package:js/js_util.dart';

import 'package:fonnx/models/sileroVad/silero_vad.dart';

SileroVad getSileroVad(String path) => SileroVadWeb(path);

@JS()
class Promise<T> {
  external Promise(
      void Function(void Function(T result) resolve, Function reject) executor);
  external Promise then(void Function(T result) onFulfilled,
      [Function onRejected]);
}

@JS('window.sileroVad')
external Promise<String> sileroVadJs(String modelPath, List<int> audioBytes, String previousStateAsJsonString);


class SileroVadWeb implements SileroVad {
  @override
  final String modelPath;

  SileroVadWeb(this.modelPath);

  @override
  Future<Map<String, dynamic>> doInference(Uint8List bytes,
      {Map<String, dynamic> previousState = const {}}) async {
    final previousStateAsJsonString = json.encode(previousState);
    final jsObject = await promiseToFuture(sileroVadJs(modelPath, bytes, previousStateAsJsonString));

    if (jsObject == null) {
      throw Exception('Silero VAD result returned from JS code is null');
    }
    final dartObject = json.decode(jsObject);
    if (dartObject is! Map<String, dynamic>) {
      throw Exception(
          'Silero VAD result returned from JS code is not a Map<String, dynamic>, it is a ${jsObject.runtimeType}');
    }

    final recasted = <String, dynamic>{};
    if (dartObject.containsKey('cn')) {
      recasted['cn'] = Float32List.fromList(dartObject['cn'].cast<double>());
    }
    if (dartObject.containsKey('hn')) {
      recasted['hn'] = Float32List.fromList(dartObject['hn'].cast<double>());
    }
    if (dartObject.containsKey('output')) {
      recasted['output'] =
          Float32List.fromList(dartObject['output'].cast<double>());
    }
    return recasted;
  }
}
