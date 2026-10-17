import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:fonnx/dylib_path_overrides.dart';
import 'package:fonnx/onnx/ort.dart';
import 'kokoro.dart';
import 'kokoro_stages.dart';
import 'kokoro_stages_ffi.dart';
import 'misaki/misaki_en.dart' show MisakiPs, MToken;
import 'misaki/misaki_fallback_ffi.dart';
import 'src/kokoro_client.dart';
import 'src/kokoro_engine.dart';

Future<Kokoro> loadKokoro(KokoroBundle bundle, KokoroChunkPolicy policy) async {
  final engine = _NativeKokoro(bundle, policy);
  try {
    await engine.start();
    return engine;
  } catch (_) {
    await engine.dispose();
    rethrow;
  }
}

/// Runs the [KokoroEngine] on one long-lived isolate.
class _NativeKokoro extends KokoroWorkerClient {
  _NativeKokoro(super.bundle, this.policy);
  final KokoroChunkPolicy policy;
  final _events = ReceivePort();
  final _errors = ReceivePort();
  final _exits = ReceivePort();
  final _ready = Completer<void>();
  final _pending = <int, Completer<Object?>>{};
  Isolate? _isolate;
  SendPort? _worker;
  int _request = 0;
  bool _disposed = false;
  Future<void>? _disposing;
  Object? _failure;

  @override
  bool get isClosing => _disposed || _disposing != null;

  @override
  bool get canCancel => !isClosing && _failure == null;

  Future<void> start() async {
    _events.listen((dynamic message) {
      if (message is SendPort) {
        _worker = message;
        _ready.complete();
        return;
      }
      final response = message as List;
      final completer = _pending.remove(response[0]);
      if (response[1] == true) {
        completer?.complete(response[2]);
      } else {
        completer?.completeError(StateError(response[2] as String));
      }
    });
    _errors.listen(
      (dynamic e) => _fail(StateError('Kokoro worker failed: $e')),
    );
    _exits.listen((_) {
      if (!_disposed) _fail(StateError('Kokoro worker exited'));
    });
    _isolate = await Isolate.spawn(
      _workerMain,
      _events.sendPort,
      onError: _errors.sendPort,
      onExit: _exits.sendPort,
    );
    await _ready.future;
    await _rpc('load', [bundle, policy, fonnxOrtDylibPathOverride]);
  }

  void _fail(Object error) {
    _failure = error;
    if (!_ready.isCompleted) _ready.completeError(error);
    for (final completer in _pending.values) {
      completer.completeError(error);
    }
    _pending.clear();
  }

  Future<Object?> _rpc(String op, [Object? payload]) {
    if (_disposed || (_disposing != null && op != 'close')) {
      return Future.error(StateError('Kokoro is disposed'));
    }
    if (_failure != null) return Future.error(_failure!);
    final id = ++_request;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _worker!.send([id, op, payload]);
    return completer.future;
  }

  @override
  Future<void> workerBegin(
    String text,
    String voice,
    double speed,
    bool normalize,
  ) => _rpc('begin', [text, voice, speed, normalize]);

  @override
  Future<KokoroEngineChunk?> workerNext() async {
    final response = await _rpc('next');
    if (response == null) return null;
    final chunk = response as List;
    return (
      samples: (chunk[0] as TransferableTypedData)
          .materialize()
          .asFloat32List(),
      isFinal: chunk[1] as bool,
      phonemes: chunk[2] as String?,
    );
  }

  @override
  Future<void> workerCancel() => _rpc('cancel');

  @override
  Future<void> dispose() => _disposing ??= _dispose();

  Future<void> _dispose() async {
    if (_disposed) return;
    try {
      if (_worker != null && _failure == null) await _rpc('close');
    } finally {
      _disposed = true;
      _fail(StateError('Kokoro is disposed'));
      _isolate?.kill();
      _events.close();
      _errors.close();
      _exits.close();
    }
  }
}

void _workerMain(SendPort parent) {
  final port = ReceivePort();
  parent.send(port.sendPort);
  KokoroEngine? engine;
  // The engine is asynchronous; requests run one at a time, in order.
  var queue = Future<void>.value();
  Future<void> handle(List m) async {
    try {
      Object? result;
      switch (m[1]) {
        case 'load':
          final data = m[2] as List;
          fonnxOrtDylibPathOverride = data[2] as String?;
          final bundle = data[0] as KokoroBundle;
          engine = await KokoroEngine.load(
            bundle,
            data[1] as KokoroChunkPolicy,
            _FfiStages(bundle),
            (path) => File(path).readAsBytes(),
          );
        case 'begin':
          final data = m[2] as List;
          await engine!.begin(
            data[0] as String,
            data[1] as String,
            data[2] as double,
            data[3] as bool,
          );
        case 'next':
          final chunk = await engine!.next();
          if (chunk != null) {
            result = [
              TransferableTypedData.fromList([chunk.samples]),
              chunk.isFinal,
              chunk.phonemes,
            ];
          }
        case 'cancel':
          engine!.cancel();
        case 'close':
          await engine?.close();
          port.close();
        default:
          throw StateError('Unknown Kokoro worker operation');
      }
      parent.send([m[0], true, result]);
    } catch (e, st) {
      parent.send([m[0], false, '$e\n$st']);
    }
  }

  port.listen((dynamic message) {
    queue = queue.then((_) => handle(message as List));
  });
}

/// The stages through dart:ffi. Each call completes synchronously.
final class _FfiStages implements KokoroStages {
  _FfiStages(KokoroBundle bundle) {
    try {
      _prosody = _session(bundle.prosodyModel);
      _decoder = _session(bundle.decoderModel);
      _fallback = MisakiFallbackFfi(
        _session(bundle.fallbackModel),
        File(bundle.fallbackConfig).readAsStringSync(),
      );
    } catch (_) {
      _release();
      rethrow;
    }
  }

  final _sessions = <OrtSessionObjects>[];
  late final OrtSessionObjects _prosody, _decoder;
  late final MisakiFallbackFfi _fallback;

  OrtSessionObjects _session(String path) {
    final s = createOrtSession(path);
    _sessions.add(s);
    return s;
  }

  @override
  Future<KokoroProsody> prosody(
    List<int> ids,
    Float32List style,
    double speed,
  ) async => runKokoroProsody(_prosody, ids: ids, style: style, speed: speed);

  @override
  Future<Float32List> decode(
    KokoroProsody prosody,
    Float32List style,
    int first,
    int last,
  ) async => runKokoroDecoder(_decoder, prosody, style, first, last);

  @override
  Future<MisakiPs> fallback(String word) async =>
      _fallback(MToken(text: word, tag: '', whitespace: ''));

  @override
  Future<void> close() async => _release();

  void _release() {
    for (final s in _sessions.reversed) {
      s.release();
    }
    _sessions.clear();
  }
}
