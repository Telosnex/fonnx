import 'dart:async';
import 'dart:typed_data';
import 'kokoro_chunking.dart';
import 'kokoro_sentence_splitter.dart';
import 'kokoro_none.dart'
    if (dart.library.io) 'kokoro_native.dart'
    if (dart.library.js_interop) 'kokoro_web.dart'
    as platform;

export 'kokoro_chunking.dart' show KokoroChunkPolicy;
export 'kokoro_sentence_splitter.dart'
    show KokoroSentenceSplit, kokoroSplitMayChange, kokoroSplitSentences;

enum KokoroLanguage { americanEnglish, britishEnglish }

class KokoroVoice {
  const KokoroVoice({required this.path, required this.language});
  final String path;
  final KokoroLanguage language;
}

/// Locations of verified artifacts: local paths on native, URLs on web. No
/// model is downloaded by the engine.
class KokoroBundle {
  KokoroBundle({
    required this.prosodyModel,
    required this.decoderModel,
    required this.spacyConfig,
    required this.spacyWeights,
    required this.usGold,
    required this.usSilver,
    required this.gbGold,
    required this.gbSilver,
    required this.fallbackModel,
    required this.fallbackConfig,
    required Map<String, KokoroVoice> voices,
  }) : voices = Map.unmodifiable(voices);

  /// Loads the layout produced by tool/kokoro/prepare_bundle.dart.
  /// Voice selection is explicit so an app need not download every voice.
  factory KokoroBundle.fromDirectory(
    String directory, {
    List<String> voiceNames = const ['af_heart', 'bf_emma'],
  }) {
    String path(String suffix) =>
        '${directory.replaceFirst(RegExp(r'[/\\]+$'), '')}/$suffix';
    return KokoroBundle(
      prosodyModel: path('onnx/stages/prosody.onnx'),
      decoderModel: path('onnx/stages/decoder.onnx'),
      spacyConfig: path('spacy/en_core_web_sm.json'),
      spacyWeights: path('spacy/en_core_web_sm_tagger.bin'),
      usGold: path('misaki/us_gold.json'),
      usSilver: path('misaki/us_silver.json'),
      gbGold: path('misaki/gb_gold.json'),
      gbSilver: path('misaki/gb_silver.json'),
      fallbackModel: path('misaki/g2p_fallback_en_us.onnx'),
      fallbackConfig: path('misaki/g2p_fallback_en_us.json'),
      voices: {
        for (final name in voiceNames)
          name: KokoroVoice(
            path: path('voices/$name.bin'),
            language: switch (name) {
              final name when RegExp(r'^a[fm]_[a-z]+$').hasMatch(name) =>
                KokoroLanguage.americanEnglish,
              final name when RegExp(r'^b[fm]_[a-z]+$').hasMatch(name) =>
                KokoroLanguage.britishEnglish,
              _ => throw ArgumentError.value(
                name,
                'voiceNames',
                'Not an English voice name',
              ),
            },
          ),
      },
    );
  }

  final String prosodyModel, decoderModel, spacyConfig, spacyWeights;
  final String usGold,
      usSilver,
      gbGold,
      gbSilver,
      fallbackModel,
      fallbackConfig;
  final Map<String, KokoroVoice> voices;
}

class KokoroChunk {
  const KokoroChunk({
    required this.samples,
    required this.utteranceId,
    required this.isFinal,
    this.text,
    this.phonemes,
    this.sourceStart,
    this.sourceEnd,
  });
  final Float32List samples;
  final int utteranceId;
  final bool isFinal;
  final String? text, phonemes;

  /// For [KokoroTextInput] audio: the unit of this chunk in all text given
  /// to [KokoroTextInput.add], as UTF-16 offsets. [sourceStart] is inclusive
  /// and [sourceEnd] is exclusive. All chunks of one unit have the same range.
  /// Ranges of later units start at or after the end of earlier ones.
  /// Null for [Kokoro.speak] and [Kokoro.synthesize].
  final int? sourceStart, sourceEnd;
  int get sampleRate => 24000;

  KokoroChunk _withSource(int start, int end) => KokoroChunk(
    samples: samples,
    utteranceId: utteranceId,
    isFinal: isFinal,
    text: text,
    phonemes: phonemes,
    sourceStart: start,
    sourceEnd: end,
  );
}

/// English-only Kokoro. Phonemes, chunking and both model stages run on one
/// long-lived worker: an isolate on native, a Web Worker on web.
///
/// On web, bundle locations are URLs, relative to the document base URI.
abstract class Kokoro {
  static Future<Kokoro> load(
    KokoroBundle bundle, {
    KokoroChunkPolicy policy = const KokoroChunkPolicy(),
  }) {
    policy.validate();
    return platform.loadKokoro(bundle, policy);
  }

  Map<String, KokoroVoice> get voices;

  Stream<KokoroChunk> speak(
    String text, {
    required String voice,
    double speed = 1,
    bool normalize = true,
  }) async* {
    validateRequest(voice, speed);
    final split = kokoroSplitSentences(text);
    if (split.remainder.length > 65536) {
      throw StateError('Unterminated input exceeds 64K characters; flush it');
    }
    final last = kokoroSplitSentences(split.remainder, finalInput: true);
    for (final unit in [...split.units, ...last.units]) {
      yield* renderUtterance(
        unit,
        voice: voice,
        speed: speed,
        normalize: normalize,
      );
    }
  }

  Future<Float32List> synthesize(
    String text, {
    required String voice,
    double speed = 1,
    bool normalize = true,
  }) async {
    final pieces = <Float32List>[];
    var count = 0;
    await for (final chunk in speak(
      text,
      voice: voice,
      speed: speed,
      normalize: normalize,
    )) {
      pieces.add(chunk.samples);
      count += chunk.samples.length;
    }
    final output = Float32List(count);
    var offset = 0;
    for (final piece in pieces) {
      output.setAll(offset, piece);
      offset += piece.length;
    }
    return output;
  }

  /// Streaming text input. See [KokoroTextInput].
  KokoroTextInput input({
    required String voice,
    double speed = 1,
    bool normalize = true,
  }) {
    validateRequest(voice, speed);
    return KokoroTextInput._(this, voice, speed, normalize);
  }

  /// Loads [voice] and runs the models once on a short text, so the first
  /// [speak] or [input] for [voice] does not pay that cost. Optional.
  Future<void> prepare(String voice) async {
    validateRequest(voice, 1);
    await renderUtterance(
      'Hi.',
      voice: voice,
      speed: 1,
      normalize: false,
    ).drain<void>();
  }

  void validateRequest(String voice, double speed) {
    if (!voices.containsKey(voice)) throw ArgumentError.value(voice, 'voice');
    if (!speed.isFinite || speed <= 0) {
      throw ArgumentError.value(speed, 'speed');
    }
  }

  /// Backend seam; consumers should use speak, synthesize, or input.
  Stream<KokoroChunk> renderUtterance(
    String text, {
    required String voice,
    required double speed,
    required bool normalize,
  });
  Future<void> dispose();
}

/// Single-subscription streaming text input. Fragments concatenate verbatim.
///
/// For LLM output: [add] each fragment as it arrives, [flush] where the text
/// pauses (for example, before a tool call), and [close] at the end.
///
/// Text that [audio] has not read yet is held in one buffer, so the number of
/// [add] calls has no limit. The buffer has a 64K character limit: [add]
/// throws rather than hold unlimited text while the audio consumer is paused.
/// Text that has no unit end also has a 64K limit; past it, [audio] gives a
/// [StateError]. Call [flush] to end a unit.
class KokoroTextInput {
  KokoroTextInput._(this._engine, this._voice, this._speed, this._normalize) {
    StreamSubscription<KokoroChunk>? units;
    late final StreamController<KokoroChunk> controller;
    controller = StreamController<KokoroChunk>(
      onListen: () {
        units = _units().listen(
          controller.add,
          onError: controller.addError,
          onDone: controller.close,
        );
      },
      onPause: () {
        units?.pause();
      },
      onResume: () {
        units?.resume();
      },
      onCancel: () {
        _cancelled = true;
        _wakeReader();
        return units?.cancel();
      },
    );
    audio = controller.stream;
  }

  final Kokoro _engine;
  final String _voice;
  final double _speed;
  final bool _normalize;
  late final Stream<KokoroChunk> audio;

  /// Text before each unread flush, oldest first. Text after the last unread
  /// flush is in [_open].
  final _flushed = <String>[];
  final _open = StringBuffer();
  Completer<void>? _wake;
  int _pending = 0;
  bool _closed = false, _cancelled = false;

  void _checkOpen() {
    if (_closed || _cancelled) throw StateError('Kokoro text input is closed');
  }

  void _wakeReader() {
    final wake = _wake;
    _wake = null;
    if (wake != null && !wake.isCompleted) wake.complete();
  }

  void add(String text) {
    _checkOpen();
    if (_pending + text.length > 65536) {
      throw StateError('Pending text exceeds 64K characters');
    }
    if (text.isEmpty) return;
    _pending += text.length;
    _open.write(text);
    _wakeReader();
  }

  /// Ends a unit at the text added so far, even with no sentence end.
  void flush() {
    _checkOpen();
    // A flush right after an unread flush adds nothing.
    if (_open.isEmpty && _flushed.isNotEmpty) return;
    _flushed.add(_open.toString());
    _open.clear();
    _wakeReader();
  }

  /// Ends the text. Pending text is still spoken. Completes at once; the
  /// [audio] stream ends after the last chunk. Closing again does nothing.
  Future<void> close() async {
    if (_closed || _cancelled) return;
    _closed = true;
    _wakeReader();
  }

  /// Renders the units of [split], which is a split of [source]. [base] is
  /// the offset of [source] in all added text.
  Stream<KokoroChunk> _render(
    KokoroSentenceSplit split,
    String source,
    int base,
  ) async* {
    var cursor = 0;
    for (final unit in split.units) {
      // Units are trimmed slices of the source, in order.
      final at = source.indexOf(unit, cursor);
      final start = at < 0 ? cursor : at;
      final end = at < 0
          ? source.length - split.remainder.length
          : at + unit.length;
      cursor = end;
      yield* _engine
          .renderUtterance(
            unit,
            voice: _voice,
            speed: _speed,
            normalize: _normalize,
          )
          .map((chunk) => chunk._withSource(base + start, base + end));
    }
  }

  Stream<KokoroChunk> _units() async* {
    // Text read from the buffer that has no unit end yet, and its offset in
    // all added text. The remainder of a split is a suffix of its source.
    var carry = '';
    var base = 0;
    while (true) {
      while (_flushed.isEmpty && _open.isEmpty && !_closed) {
        await (_wake = Completer<void>()).future;
        if (_cancelled) return;
      }
      if (_cancelled) return;
      final flushed = List.of(_flushed);
      final open = _open.toString();
      final closed = _closed;
      _flushed.clear();
      _open.clear();
      _pending = 0;
      for (final text in flushed) {
        final source = carry + text;
        final split = kokoroSplitSentences(source, finalInput: true);
        yield* _render(split, source, base);
        carry = '';
        base += source.length;
      }
      if (closed || kokoroSplitMayChange(carry, open)) {
        final source = carry + open;
        final split = kokoroSplitSentences(source, finalInput: closed);
        yield* _render(split, source, base);
        carry = split.remainder;
        base += source.length - carry.length;
      } else {
        carry += open;
      }
      if (carry.length > 65536) {
        throw StateError('Unterminated input exceeds 64K characters; flush it');
      }
      if (closed) return;
    }
  }
}
