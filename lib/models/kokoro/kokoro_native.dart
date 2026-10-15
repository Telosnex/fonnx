import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:fonnx/dylib_path_overrides.dart';
import 'package:fonnx/onnx/ort.dart';
import 'kokoro.dart';
import 'kokoro_chunking.dart';
import 'kokoro_ffi.dart';
import 'kokoro_normalizer.dart';
import 'kokoro_stages_ffi.dart';
import 'misaki/misaki.dart';
import 'misaki/misaki_fallback_ffi.dart';

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

class _NativeKokoro extends Kokoro {
  _NativeKokoro(this.bundle, this.policy);
  final KokoroBundle bundle;
  final KokoroChunkPolicy policy;
  final _events = ReceivePort();
  final _errors = ReceivePort();
  final _exits = ReceivePort();
  final _ready = Completer<void>();
  final _pending = <int, Completer<Object?>>{};
  Isolate? _isolate;
  SendPort? _worker;
  int _request = 0, _utterance = 0;
  bool _disposed = false;
  Future<void>? _disposing;
  Object? _failure;
  Future<void> _queue = Future.value();
  @override
  Map<String, KokoroVoice> get voices => bundle.voices;

  @override
  void validateRequest(String voice, double speed) {
    if (_disposed || _disposing != null) throw StateError('Kokoro is disposed');
    super.validateRequest(voice, speed);
  }

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
  Stream<KokoroChunk> renderUtterance(
    String text, {
    required String voice,
    required double speed,
    required bool normalize,
  }) {
    late StreamController<KokoroChunk> controller;
    final cancelled = Completer<void>();
    final finished = Completer<void>();
    Completer<void>? paused;
    var isCancelled = false;
    Future<void> produce() async {
      final previous = _queue;
      final release = Completer<void>();
      // Cancelling a queued request must not let the next request overtake
      // the still-active predecessor.
      _queue = previous.then((_) => release.future);
      var begun = false;
      var textSent = false;
      try {
        await Future.any([previous, cancelled.future]);
        if (isCancelled) return;
        await _rpc('begin', [text, voice, speed, normalize]);
        begun = true;
        while (!isCancelled) {
          if (paused != null) await paused!.future;
          if (isCancelled) break;
          final response = await _rpc('next');
          if (response == null || isCancelled) break;
          if (paused != null) await paused!.future;
          if (isCancelled) break;
          final chunk = response as List;
          // One text unit is one utterance, even when its phonemes are
          // decoded in several parts.
          final first = !textSent;
          if (first) _utterance++;
          controller.add(
            KokoroChunk(
              samples: (chunk[0] as TransferableTypedData)
                  .materialize()
                  .asFloat32List(),
              utteranceId: _utterance,
              isFinal: chunk[2] as bool,
              text: first ? text : null,
              phonemes: chunk[3] as String?,
            ),
          );
          if (first) textSent = true;
          // Let subscription pause/cancel callbacks run before another decode.
          await Future<void>.delayed(Duration.zero);
        }
      } catch (e, st) {
        if (!isCancelled) controller.addError(e, st);
      } finally {
        try {
          if (begun && !_disposed && _disposing == null && _failure == null) {
            await _rpc('cancel');
          }
        } catch (e, st) {
          if (!isCancelled) controller.addError(e, st);
        } finally {
          release.complete();
          finished.complete();
          unawaited(controller.close());
        }
      }
    }

    controller = StreamController<KokoroChunk>(
      sync: true,
      onListen: () {
        unawaited(produce());
      },
      onPause: () {
        paused ??= Completer<void>();
      },
      onResume: () {
        paused?.complete();
        paused = null;
      },
      onCancel: () {
        isCancelled = true;
        if (!cancelled.isCompleted) cancelled.complete();
        paused?.complete();
        paused = null;
        return finished.future;
      },
    );
    return controller.stream;
  }

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
  _Backend? engine;
  port.listen((dynamic message) {
    final m = message as List;
    try {
      Object? result;
      switch (m[1]) {
        case 'load':
          final data = m[2] as List;
          fonnxOrtDylibPathOverride = data[2] as String?;
          engine = _Backend(
            data[0] as KokoroBundle,
            data[1] as KokoroChunkPolicy,
          );
        case 'begin':
          final data = m[2] as List;
          engine!.begin(
            data[0] as String,
            data[1] as String,
            data[2] as double,
            data[3] as bool,
          );
        case 'next':
          result = engine!.next();
        case 'cancel':
          engine!.cancel();
        case 'close':
          engine?.close();
          port.close();
        default:
          throw StateError('Unknown Kokoro worker operation');
      }
      parent.send([m[0], true, result]);
    } catch (e, st) {
      parent.send([m[0], false, '$e\n$st']);
    }
  });
}

class _Backend {
  _Backend(this.bundle, this.policy) {
    try {
      prosodySession = _session(bundle.prosodyModel);
      decoderSession = _session(bundle.decoderModel);
      final fallbackSession = _session(bundle.fallbackModel);
      final fallback = MisakiFallbackFfi(
        fallbackSession,
        File(bundle.fallbackConfig).readAsStringSync(),
      );
      Map<String, dynamic> json(String path) =>
          jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
      us = Misaki.load(
        gold: json(bundle.usGold),
        silver: json(bundle.usSilver),
        spacyConfigJson: File(bundle.spacyConfig).readAsStringSync(),
        spacyWeights: File(bundle.spacyWeights).readAsBytesSync(),
        fallback: fallback.call,
        unk: '',
      );
      gb = Misaki(
        spacy: us.spacy,
        g2p: MisakiG2P(
          lexicon: MisakiLexicon(
            gold: json(bundle.gbGold),
            silver: json(bundle.gbSilver),
            british: true,
          ),
          fallback: fallback.call,
          unk: '',
        ),
      );
      if (bundle.voices.isEmpty) {
        throw ArgumentError('At least one voice is required');
      }
    } catch (_) {
      close();
      rethrow;
    }
  }
  final KokoroBundle bundle;
  final KokoroChunkPolicy policy;
  final _sessions = <OrtSessionObjects>[];
  late final OrtSessionObjects prosodySession, decoderSession;
  late final Misaki us, gb;
  final _voices = <String, Float32List>{};
  OrtSessionObjects _session(String path) {
    final s = createOrtSession(path);
    _sessions.add(s);
    return s;
  }

  List<String> _phonemes = [];
  int _part = 0, _span = 0;
  List<KokoroChunkSpan> _spans = [];
  KokoroProsody? _prosody;
  Float32List? _style;
  late Float32List _voice;
  late double _speed;
  late KokoroSliceJoiner _joiner;
  double _decodeCost = 0;

  void begin(String text, String name, double speed, bool normalize) {
    cancel();
    final voice = bundle.voices[name];
    if (voice == null || !speed.isFinite || speed <= 0) {
      throw ArgumentError('Invalid voice or speed');
    }
    _voice = _voices.putIfAbsent(name, () {
      final bytes = File(voice.path).readAsBytesSync();
      if (bytes.length != 510 * 256 * 4) {
        throw FormatException('Invalid Kokoro voice shape: $name');
      }
      final data = ByteData.sublistView(bytes);
      final values = Float32List(bytes.length ~/ 4);
      for (var i = 0; i < values.length; i++) {
        values[i] = data.getFloat32(i * 4, Endian.little);
      }
      if (values.any((v) => !v.isFinite)) {
        throw FormatException('Nonfinite voice values: $name');
      }
      return values;
    });
    _speed = speed;
    final misaki = voice.language == KokoroLanguage.americanEnglish ? us : gb;
    _phonemes = [
      for (final part in kokoroSplitPhonemes(
        misaki.phonemize(normalize ? normalizeKokoroEnglish(text) : text),
      ))
        if (kokoroPhonemesToIds(part).isNotEmpty) part,
    ];
  }

  Object? next() {
    while (_span >= _spans.length) {
      if (_part >= _phonemes.length) {
        cancel();
        return null;
      }
      final phonemes = _phonemes[_part++];
      final ids = kokoroPhonemesToIds(phonemes);
      _style = kokoroStyleForLength(_voice, phonemes.runes.length);
      _prosody = runKokoroProsody(
        prosodySession,
        ids: ids,
        style: _style!,
        speed: _speed,
      );
      final p = _prosody!;
      final adjusted = KokoroChunkPolicy(
        firstChunkSeconds: policy.firstChunkSeconds,
        toleranceSeconds: policy.toleranceSeconds,
        crossfadeSeconds: policy.crossfadeSeconds,
        padFrames: policy.padFrames,
        growth: _decodeCost > 0
            ? policy.growth
                  .clamp(1, policy.maxSustainableGrowth(_decodeCost))
                  .toDouble()
            : policy.growth,
      );
      _spans = kokoroPlanSpans(
        kokoroPlanBoundaries(
          kokoroBoundaryCost(p.f0.data, p.energy.data, p.frames),
          p.frames,
          policy: adjusted,
          speech: kokoroSpeechFrames(p.energy.data, p.frames),
        ),
        p.frames,
        policy: adjusted,
      );
      _joiner = KokoroSliceJoiner(policy: adjusted);
      _span = 0;
    }
    final span = _spans[_span];
    final timer = Stopwatch()..start();
    final decoded = runKokoroDecoder(
      decoderSession,
      _prosody!,
      _style!,
      span.decodeFirst,
      span.decodeLast,
    );
    _decodeCost =
        timer.elapsedMicroseconds / 1000000 / (decoded.length / 24000);
    final first = _span == 0 && _part == 1;
    _span++;
    // Each phoneme part has its own prosody and joiner; flush its tail.
    final partLast = _span == _spans.length;
    final last = partLast && _part == _phonemes.length;
    final offset = span.decodeFirst * 600;
    final audio = _joiner.add(
      Float32List.sublistView(
        decoded,
        span.keepFirst - offset,
        span.keepLast - offset,
      ),
      last: partLast,
    );
    return [
      TransferableTypedData.fromList([audio]),
      first,
      last,
      first ? _phonemes.join(' ') : null,
    ];
  }

  void cancel() {
    _phonemes = [];
    _part = 0;
    _spans = [];
    _span = 0;
    _prosody = null;
    _style = null;
  }

  void close() {
    cancel();
    for (final s in _sessions.reversed) {
      s.release();
    }
    _sessions.clear();
    _voices.clear();
  }
}
