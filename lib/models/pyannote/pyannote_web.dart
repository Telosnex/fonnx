import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'pyannote.dart';

Pyannote getPyannote(String path) => PyannoteWeb(path);

@JS('window.pyannote')
external JSPromise<JSString?> pyannoteFn(
  String modelPath, 
  JSFloat32Array audioData,
);

class PyannoteWeb implements Pyannote {
  @override
  final String modelPath;

  PyannoteWeb(this.modelPath);

  @override
  Future<List<Map<String, dynamic>>> process(Float32List audioData) async {
    final jsObject = await pyannoteFn(
      modelPath,
      audioData.toJS,
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

    final List<Map<String, dynamic>> results = [];
    for (final segment in dartObject) {
      if (segment is! Map) {
        throw Exception('Segment is not a Map: $segment');
      }
      
      final speakerIndex = segment['speaker'];
      final start = segment['start'];
      final stop = segment['stop'];
      
      if (speakerIndex is! num || start is! num || stop is! num) {
        throw Exception('Invalid segment format: $segment');
      }
      
      results.add({
        'speaker': speakerIndex,
        'start': start.toDouble(),
        'stop': stop.toDouble(),
      });
    }

    return results;
  }
}