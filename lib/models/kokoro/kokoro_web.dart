import 'dart:convert';
import 'dart:js_interop';

import 'package:fonnx/src/web_loader.dart';

import 'kokoro.dart';
import 'src/kokoro_client.dart';
import 'src/kokoro_engine.dart';
import 'src/kokoro_wire.dart';

Future<Kokoro> loadKokoro(KokoroBundle bundle, KokoroChunkPolicy policy) async {
  final engine = _WebKokoro(bundle);
  try {
    await engine.start(policy);
    return engine;
  } catch (_) {
    await engine.dispose();
    rethrow;
  }
}

/// Kokoro on web. Phonemes, chunking and both stages run in one Web Worker
/// (lib/web/kokoro_worker.js); this side only carries requests.
class _WebKokoro extends KokoroWorkerClient {
  _WebKokoro(super.bundle)
    : _id =
          'fonnx-kokoro-${DateTime.now().microsecondsSinceEpoch}-${_nextId++}';

  static var _nextId = 0;
  final String _id;
  bool _loaded = false, _disposed = false;
  Future<void>? _disposing;

  @override
  bool get isClosing => _disposed || _disposing != null;

  @override
  bool get canCancel => !isClosing;

  Future<void> start(KokoroChunkPolicy policy) async {
    await loadFonnxWebModule('kokoro_init.js');
    // The Worker resolves relative URLs against its own script URL.
    final base = Uri.parse(_documentBaseUri);
    final request = kokoroLoadRequestToJson(
      bundle,
      policy,
      resolve: (location) => base.resolve(location).toString(),
    );
    await _load(_id.toJS, jsonEncode(request).toJS).toDart;
    _loaded = true;
  }

  void _checkOpen() {
    if (_disposed) throw StateError('Kokoro is disposed');
  }

  @override
  Future<void> workerBegin(
    String text,
    String voice,
    double speed,
    bool normalize,
  ) async {
    _checkOpen();
    await _begin(
      _id.toJS,
      text.toJS,
      voice.toJS,
      speed.toJS,
      normalize.toJS,
    ).toDart;
  }

  @override
  Future<KokoroEngineChunk?> workerNext() async {
    _checkOpen();
    final chunk = await _next(_id.toJS).toDart;
    if (chunk == null) return null;
    return (
      samples: chunk.samples.toDart,
      isFinal: chunk.isFinal,
      phonemes: chunk.phonemes,
    );
  }

  @override
  Future<void> workerCancel() async {
    _checkOpen();
    await _cancel(_id.toJS).toDart;
  }

  @override
  Future<void> dispose() => _disposing ??= _dispose();

  Future<void> _dispose() async {
    try {
      if (_loaded) await _close(_id.toJS).toDart;
    } finally {
      _disposed = true;
    }
  }
}

@JS('document.baseURI')
external String get _documentBaseUri;

@JS('window.fonnxKokoroLoad')
external JSPromise<JSAny?> _load(JSString id, JSString request);

@JS('window.fonnxKokoroBegin')
external JSPromise<JSAny?> _begin(
  JSString id,
  JSString text,
  JSString voice,
  JSNumber speed,
  JSBoolean normalize,
);

@JS('window.fonnxKokoroNext')
external JSPromise<_Chunk?> _next(JSString id);

@JS('window.fonnxKokoroCancel')
external JSPromise<JSAny?> _cancel(JSString id);

@JS('window.fonnxKokoroClose')
external JSPromise<JSAny?> _close(JSString id);

extension type _Chunk._(JSObject _) implements JSObject {
  external JSFloat32Array get samples;
  external bool get isFinal;
  external String? get phonemes;
}
