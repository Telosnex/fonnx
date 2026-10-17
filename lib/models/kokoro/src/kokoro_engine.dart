import 'dart:convert';
import 'dart:typed_data';

import '../kokoro.dart';
import '../kokoro_chunking.dart';
import '../kokoro_normalizer.dart';
import '../kokoro_stages.dart';
import '../kokoro_tokens.dart';
import '../misaki/misaki.dart';
import '../misaki/misaki_en.dart' show MisakiPs;

/// Reads a bundle file: a path on native, a URL on web.
typedef KokoroReader = Future<Uint8List> Function(String location);

/// One decoded part of an utterance.
typedef KokoroEngineChunk = ({
  Float32List samples,
  bool isFinal,
  String? phonemes,
});

/// Kokoro synthesis on one worker: native isolate or web Worker.
///
/// It runs one request at a time. [begin] phonemizes the text, and each
/// [next] decodes one span.
final class KokoroEngine {
  KokoroEngine._(this._bundle, this._policy, this._stages, this._read);

  /// Loads the phonemizer data of [bundle]. [stages] holds the sessions; the
  /// engine closes them.
  static Future<KokoroEngine> load(
    KokoroBundle bundle,
    KokoroChunkPolicy policy,
    KokoroStages stages,
    KokoroReader read,
  ) async {
    final engine = KokoroEngine._(bundle, policy, stages, read);
    try {
      if (bundle.voices.isEmpty) {
        throw ArgumentError('At least one voice is required');
      }
      Future<String> text(String location) async =>
          utf8.decode(await read(location));
      Future<Map<String, dynamic>> json(String location) async =>
          jsonDecode(await text(location)) as Map<String, dynamic>;
      final fallback = engine._words.call;
      final us = Misaki.load(
        gold: await json(bundle.usGold),
        silver: await json(bundle.usSilver),
        spacyConfigJson: await text(bundle.spacyConfig),
        spacyWeights: await read(bundle.spacyWeights),
        fallback: fallback,
        unk: '',
      );
      final gb = Misaki(
        spacy: us.spacy,
        g2p: MisakiG2P(
          lexicon: MisakiLexicon(
            gold: await json(bundle.gbGold),
            silver: await json(bundle.gbSilver),
            british: true,
          ),
          fallback: fallback,
          unk: '',
        ),
      );
      engine
        .._us = us
        .._gb = gb;
      return engine;
    } catch (_) {
      await engine.close();
      rethrow;
    }
  }

  final KokoroBundle _bundle;
  final KokoroChunkPolicy _policy;
  final KokoroStages _stages;
  final KokoroReader _read;
  late final _words = _FallbackWords(_stages.fallback);
  late final Misaki _us, _gb;
  final _voices = <String, Float32List>{};

  List<String> _phonemes = [];
  int _part = 0, _span = 0;
  List<KokoroChunkSpan> _spans = [];
  KokoroProsody? _prosody;
  Float32List? _style;
  late Float32List _voice;
  late double _speed;
  late KokoroSliceJoiner _joiner;
  double _decodeCost = 0;

  Future<void> begin(
    String text,
    String name,
    double speed,
    bool normalize,
  ) async {
    cancel();
    final voice = _bundle.voices[name];
    if (voice == null || !speed.isFinite || speed <= 0) {
      throw ArgumentError('Invalid voice or speed');
    }
    _voice = _voices[name] ??= kokoroParseVoice(await _read(voice.path), name);
    _speed = speed;
    final misaki = voice.language == KokoroLanguage.americanEnglish ? _us : _gb;
    final phonemes = await _words.phonemize(
      misaki,
      normalize ? normalizeKokoroEnglish(text) : text,
    );
    _phonemes = [
      for (final part in kokoroSplitPhonemes(phonemes))
        if (kokoroPhonemesToIds(part).isNotEmpty) part,
    ];
  }

  /// The next span of the current request, or null after the last.
  Future<KokoroEngineChunk?> next() async {
    while (_span >= _spans.length) {
      if (_part >= _phonemes.length) {
        cancel();
        return null;
      }
      final phonemes = _phonemes[_part++];
      final ids = kokoroPhonemesToIds(phonemes);
      _style = kokoroStyleForLength(_voice, phonemes.runes.length);
      final p = _prosody = await _stages.prosody(ids, _style!, _speed);
      final adjusted = KokoroChunkPolicy(
        firstChunkSeconds: _policy.firstChunkSeconds,
        toleranceSeconds: _policy.toleranceSeconds,
        crossfadeSeconds: _policy.crossfadeSeconds,
        padFrames: _policy.padFrames,
        decodeSpeechFrames: _policy.decodeSpeechFrames,
        growth: _decodeCost > 0
            ? _policy.growth
                  .clamp(1, _policy.maxSustainableGrowth(_decodeCost))
                  .toDouble()
            : _policy.growth,
      );
      final speech = kokoroSpeechFrames(p.energy.data, p.frames);
      _spans = kokoroPlanSpans(
        kokoroPlanBoundaries(
          kokoroBoundaryCost(p.f0.data, p.energy.data, p.frames),
          p.frames,
          policy: adjusted,
          speech: speech,
        ),
        p.frames,
        policy: adjusted,
        speech: speech,
      );
      _joiner = KokoroSliceJoiner(policy: adjusted);
      _span = 0;
    }
    final span = _spans[_span];
    final timer = Stopwatch()..start();
    final decoded = await _stages.decode(
      _prosody!,
      _style!,
      span.decodeFirst,
      span.decodeLast,
    );
    if (decoded.length != (span.decodeLast - span.decodeFirst) * 600) {
      throw StateError('Decoder returned an unexpected sample count');
    }
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
    return (
      samples: audio,
      isFinal: last,
      phonemes: first ? _phonemes.join(' ') : null,
    );
  }

  void cancel() {
    _phonemes = [];
    _part = 0;
    _spans = [];
    _span = 0;
    _prosody = null;
    _style = null;
  }

  Future<void> close() async {
    cancel();
    _voices.clear();
    await _stages.close();
  }
}

/// misaki calls its fallback synchronously, and ORT Web runs asynchronously.
///
/// [phonemize] runs misaki with the known words. It then computes the words
/// that misaki asked for, and runs again, until misaki asks for no new word.
/// The last run answers every call as a synchronous fallback would, so the
/// phonemes are the same. The fallback depends only on the word text.
final class _FallbackWords {
  _FallbackWords(this._compute);

  final Future<MisakiPs> Function(String word) _compute;
  final _known = <String, MisakiPs>{};
  final _missing = <String>{};

  /// Bounds the memory of a long session.
  static const _maxKnown = 4096;

  MisakiPs call(MToken token) {
    final known = _known[token.text];
    if (known != null) return known;
    _missing.add(token.text);
    return (null, null);
  }

  Future<String> phonemize(Misaki misaki, String text) async {
    if (_known.length > _maxKnown) _known.clear();
    while (true) {
      _missing.clear();
      final phonemes = misaki.phonemize(text);
      if (_missing.isEmpty) return phonemes;
      final words = _missing.toList();
      for (final word in words) {
        _known[word] = await _compute(word);
      }
    }
  }
}
