/// The Dart program of the Kokoro web Worker, compiled to
/// `lib/web/kokoro_engine.dart.js` by tool/kiln/build_web.dart. It runs the
/// phonemizer and the chunking in the Worker, so they never block the page
/// (ADR 002 R3). `lib/web/kokoro_worker.js` loads ORT Web, provides the ORT
/// calls as `self.fonnxKokoroOrt`, and passes the requests on.
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import '../kokoro_stages.dart';
import '../misaki/misaki_en.dart' show MisakiPs;
import '../misaki/misaki_fallback.dart';
import '../src/kokoro_engine.dart';
import '../src/kokoro_wire.dart';

void main() {
  final engines = <String, KokoroEngine>{};
  KokoroEngine engine(String id) =>
      engines[id] ?? (throw StateError('Unknown Kokoro engine: $id'));

  JSPromise<_Result> load(JSString id, JSString request) => _guard(() async {
    final (bundle, policy) = kokoroLoadRequestFromJson(
      jsonDecode(request.toDart) as Map<String, dynamic>,
    );
    final stages = await _WebStages.load(
      id.toDart,
      bundle.prosodyModel,
      bundle.decoderModel,
      bundle.fallbackModel,
      utf8.decode(await _read(bundle.fallbackConfig)),
    );
    final created = await KokoroEngine.load(bundle, policy, stages, _read);
    await engines.remove(id.toDart)?.close();
    engines[id.toDart] = created;
    return null;
  });

  JSPromise<_Result> begin(
    JSString id,
    JSString text,
    JSString voice,
    JSNumber speed,
    JSBoolean normalize,
  ) => _guard(() async {
    await engine(
      id.toDart,
    ).begin(text.toDart, voice.toDart, speed.toDartDouble, normalize.toDart);
    return null;
  });

  JSPromise<_Result> next(JSString id) => _guard(() async {
    final chunk = await engine(id.toDart).next();
    if (chunk == null) return null;
    return _Chunk(
      samples: chunk.samples.toJS,
      isFinal: chunk.isFinal.toJS,
      phonemes: chunk.phonemes?.toJS,
    );
  });

  JSPromise<_Result> cancel(JSString id) => _guard(() async {
    engines[id.toDart]?.cancel();
    return null;
  });

  JSPromise<_Result> close(JSString id) => _guard(() async {
    await engines.remove(id.toDart)?.close();
    return null;
  });

  _ready(
    _Api(
      load: load.toJS,
      begin: begin.toJS,
      next: next.toJS,
      cancel: cancel.toJS,
      close: close.toJS,
    ),
  );
}

/// Resolves to `{value}`, or to `{error}` with the Dart message and stack.
/// kokoro_worker.js throws the error. A Dart error does not convert to a
/// useful JavaScript rejection.
JSPromise<_Result> _guard(Future<JSAny?> Function() body) {
  Future<_Result> run() async {
    try {
      return _Result(value: await body());
    } catch (e, st) {
      return _Result(error: '$e\n$st'.toJS);
    }
  }

  return run().toJS;
}

Future<Uint8List> _read(String url) async {
  final response = await _fetch(url.toJS).toDart;
  if (!response.ok) {
    throw StateError('Kokoro: GET $url: HTTP ${response.status}');
  }
  return (await response.arrayBuffer().toDart).toDart.asUint8List();
}

final class _WebStages implements KokoroStages {
  _WebStages._(this._id, this._vocab);

  static Future<_WebStages> load(
    String id,
    String prosody,
    String decoder,
    String fallback,
    String fallbackConfig,
  ) async {
    final vocab = MisakiFallbackVocab(fallbackConfig);
    await _ort.load(id.toJS, prosody.toJS, decoder.toJS, fallback.toJS).toDart;
    return _WebStages._(id, vocab);
  }

  final String _id;
  final MisakiFallbackVocab _vocab;

  @override
  Future<KokoroProsody> prosody(
    List<int> ids,
    Float32List style,
    double speed,
  ) async {
    kokoroCheckProsodyRequest(ids, speed);
    final r = await _ort
        .prosody(
          _id.toJS,
          Int32List.fromList([0, ...ids, 0]).toJS,
          style.toJS,
          speed.toJS,
        )
        .toDart;
    final frames = r.frames.toDartInt;
    return KokoroProsody(
      KokoroTensor(r.asr.toDart, [1, 512, frames]),
      KokoroTensor(r.f0.toDart, [1, 2 * frames]),
      KokoroTensor(r.n.toDart, [1, 2 * frames]),
    );
  }

  @override
  Future<Float32List> decode(
    KokoroProsody prosody,
    Float32List style,
    int first,
    int last,
  ) async {
    final inputs = kokoroDecoderInputs(prosody, first, last);
    return (await _ort
            .decode(
              _id.toJS,
              inputs.asr.toJS,
              inputs.f0.toJS,
              inputs.energy.toJS,
              style.toJS,
              (last - first).toJS,
            )
            .toDart)
        .toDart;
  }

  @override
  Future<MisakiPs> fallback(String word) => _vocab.decode(
    word,
    (src, dec) async =>
        (await _ort
                .fallbackNext(
                  _id.toJS,
                  Int32List.fromList(src).toJS,
                  Int32List.fromList(dec).toJS,
                )
                .toDart)
            .toDartInt,
  );

  @override
  Future<void> close() async {
    await _ort.close(_id.toJS).toDart;
  }
}

@JS('fonnxKokoroEngineReady')
external void _ready(_Api api);

@JS('fonnxKokoroOrt')
external _Ort get _ort;

@JS('fetch')
external JSPromise<_Response> _fetch(JSString url);

extension type _Result._(JSObject _) implements JSObject {
  external factory _Result({JSAny? value, JSString? error});
}

extension type _Response._(JSObject _) implements JSObject {
  external bool get ok;
  external int get status;
  external JSPromise<JSArrayBuffer> arrayBuffer();
}

extension type _Api._(JSObject _) implements JSObject {
  external factory _Api({
    JSFunction load,
    JSFunction begin,
    JSFunction next,
    JSFunction cancel,
    JSFunction close,
  });
}

extension type _Chunk._(JSObject _) implements JSObject {
  external factory _Chunk({
    JSFloat32Array samples,
    JSBoolean isFinal,
    JSString? phonemes,
  });
}

extension type _ProsodyResult._(JSObject _) implements JSObject {
  external JSFloat32Array get asr;
  external JSFloat32Array get f0;
  external JSFloat32Array get n;
  external JSNumber get frames;
}

/// The ORT calls of lib/web/kokoro_worker.js.
extension type _Ort._(JSObject _) implements JSObject {
  external JSPromise<JSBoolean> load(
    JSString id,
    JSString prosody,
    JSString decoder,
    JSString fallback,
  );
  external JSPromise<_ProsodyResult> prosody(
    JSString id,
    JSInt32Array ids,
    JSFloat32Array style,
    JSNumber speed,
  );
  external JSPromise<JSFloat32Array> decode(
    JSString id,
    JSFloat32Array asr,
    JSFloat32Array f0,
    JSFloat32Array n,
    JSFloat32Array style,
    JSNumber frames,
  );
  external JSPromise<JSNumber> fallbackNext(
    JSString id,
    JSInt32Array src,
    JSInt32Array dec,
  );
  external JSPromise<JSBoolean> close(JSString id);
}
