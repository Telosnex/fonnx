import 'dart:js_interop';
import 'dart:typed_data';

import 'package:fonnx/src/web_loader.dart';

import 'src/wolf_defender_engine.dart';
import 'src/wolf_defender_tokenizer.dart';
import 'wolf_defender.dart';

WolfDefender getWolfDefender(WolfDefenderBundle bundle) =>
    WolfDefenderWeb(bundle);

@JS('window.fonnxWolfDefenderLoad')
external JSPromise<JSAny?> _loadJs(JSString engineId, JSString path);

@JS('window.fonnxWolfDefenderRun')
external JSPromise<JSFloat32Array> _runJs(JSString engineId, JSInt32Array ids);

@JS('window.fonnxWolfDefenderClose')
external JSPromise<JSAny?> _closeJs(JSString engineId);

@JS('fetch')
external JSPromise<_Response> _fetch(JSString url);

extension type _Response._(JSObject _) implements JSObject {
  external bool get ok;
  external int get status;
  external JSPromise<JSArrayBuffer> arrayBuffer();
}

/// Wolf Defender on web. The ORT session lives in a Web Worker. The tokenizer
/// and the pooling run here, in the same Dart code as native.
class WolfDefenderWeb implements WolfDefender {
  WolfDefenderWeb(this.bundle);

  @override
  final WolfDefenderBundle bundle;

  final _backend = WebWolfDefenderOnnxBackend();
  Future<WolfDefenderEngine>? _engine;
  Future<void> _pending = Future<void>.value();

  @override
  Future<WolfDefenderResult> classify(String text) => _enqueue(() async {
    final engine = await (_engine ??= _load().catchError((Object error) {
      _engine = null;
      throw error;
    }));
    return engine.classify(text);
  });

  Future<WolfDefenderEngine> _load() async {
    final response = await _fetch(bundle.tokenizerPath.toJS).toDart;
    if (!response.ok) {
      throw StateError(
        'Wolf Defender tokenizer ${bundle.tokenizerPath}: '
        'HTTP ${response.status}',
      );
    }
    final tokenizer = WolfDefenderTokenizer.fromBytes(
      (await response.arrayBuffer().toDart).toDart.asUint8List(),
    );
    await _backend.load(bundle.modelPath);
    return WolfDefenderEngine(_backend, tokenizer);
  }

  /// Runs one classification at a time.
  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final result = _pending.then((_) => operation());
    _pending = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }
}

final class WebWolfDefenderOnnxBackend implements WolfDefenderOnnxBackend {
  WebWolfDefenderOnnxBackend()
    : _engineId =
          'fonnx-wolf-defender-${DateTime.now().microsecondsSinceEpoch}-'
          '${_nextId++}';

  static var _nextId = 0;
  final String _engineId;

  Future<void> load(String modelPath) async {
    await loadFonnxWebModule('wolf_defender_init.js');
    await _loadJs(_engineId.toJS, modelPath.toJS).toDart;
  }

  @override
  Future<Float32List> run(Int32List ids) async =>
      (await _runJs(_engineId.toJS, ids.toJS).toDart).toDart;

  @override
  Future<void> close() async {
    await _closeJs(_engineId.toJS).toDart;
  }
}
