import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'pyannote.dart';

Pyannote getPyannote(String path, String modelName) => PyannoteWeb(path, modelName);

@JS('window.pyannote')
external JSPromise<JSString?> pyannoteFn(String modelPath, String modelName, JSFloat32Array audioData, String config);

class PyannoteWeb implements Pyannote {
  @override
  final String modelPath;

  @override
  final String modelName;

  PyannoteWeb(this.modelPath, this.modelName);

  @override
  Future<List<Map<String, dynamic>>> process(Float32List audioData, {double? step}) async {
    final config = {
      'step': step,
    };
    final configString = json.encode(config);
    
    final jsObject = await pyannoteFn(
      modelPath, 
      modelName, 
      audioData.toJS, 
      configString
    ).toDart;

    if (jsObject == null) {
      throw Exception('Pyannote result returned from JS code is null');
    }
    
    final dartObject = json.decode(jsObject.toDart);
    if (dartObject is! List) {
      throw Exception(
        'Pyannote result returned from JS code is not a List, it is a ${dartObject.runtimeType}',
      );
    }

    return dartObject.cast<Map<String, dynamic>>();
  }
}