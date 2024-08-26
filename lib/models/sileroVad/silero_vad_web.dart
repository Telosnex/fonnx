import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:fonnx/models/sileroVad/silero_vad.dart';

SileroVad getSileroVad(String path) => SileroVadWeb(path);

@JS('window.sileroVad')
external JSPromise<JSString?> sileroVadJs(String modelPath,
    JSUint8Array audioBytes, String previousStateAsJsonString);

class SileroVadWeb implements SileroVad {
  @override
  final String modelPath;

  SileroVadWeb(this.modelPath);

  @override
  Future<Map<String, dynamic>> doInference(Uint8List bytes,
      {Map<String, dynamic> previousState = const {}}) async {
    final previousStateAsJsonString = json.encode(previousState);
    final jsObject =
        await sileroVadJs(modelPath, bytes.toJS, previousStateAsJsonString)
            .toDart;

    if (jsObject == null) {
      throw Exception('Silero VAD result returned from JS code is null');
    }
    final dartObject = json.decode(jsObject.toDart);
    if (dartObject is! Map<String, dynamic>) {
      throw Exception(
          'Silero VAD result returned from JS code is not a Map<String, dynamic>, it is a ${jsObject.runtimeType}');
    }

    final recasted = <String, dynamic>{};
    final keysToRecast = ['cn', 'hn', 'output'];

    for (final key in keysToRecast) {
      if (!dartObject.containsKey(key)) {
        continue;
      }

      final List<dynamic> array = dartObject[key];
      if (array.isEmpty) {
        continue;
      }

      // Convert all elements to double, handling both int and double
      // - We used to be able to assume that the JS was List<double>
      // - WASM x Flutter Web introduced an issue - decoded JSON has a List
      //   that are both int and double. This seems to happen on louder input,
      //   my guess is 1.0 is being converted to 1 in JS.
      // - Without this recasting, Dart code crashes in WASM.
      final List<double> doubleArray =
          array.map((e) => e is int ? e.toDouble() : (e as double)).toList();
      recasted[key] = Float32List.fromList(doubleArray);
    }
    return recasted;
  }
}
