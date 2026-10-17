import 'dart:js_interop';
import 'dart:typed_data';

/// The text of [path], relative to test/.
Future<String> readTestText(String path) async =>
    (await (await _get(path)).text().toDart).toDart;

/// The bytes of [path], relative to test/.
Future<Uint8List> readTestBytes(String path) async =>
    (await (await _get(path)).arrayBuffer().toDart).toDart.asUint8List();

Future<_Response> _get(String path) async {
  final response = await _fetch('/$path'.toJS).toDart;
  if (!response.ok) throw StateError('GET /$path: HTTP ${response.status}');
  return response;
}

@JS('fetch')
external JSPromise<_Response> _fetch(JSString url);

extension type _Response(JSObject _) implements JSObject {
  external bool get ok;
  external int get status;
  external JSPromise<JSString> text();
  external JSPromise<JSArrayBuffer> arrayBuffer();
}
