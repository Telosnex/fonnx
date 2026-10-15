import 'dart:async';
import 'dart:typed_data';
import 'kokoro_chunking.dart';
import 'kokoro_sentence_splitter.dart';
import 'kokoro_none.dart' if (dart.library.io) 'kokoro_native.dart' as platform;

export 'kokoro_chunking.dart' show KokoroChunkPolicy;

enum KokoroLanguage { americanEnglish, britishEnglish }

class KokoroVoice {
  const KokoroVoice({required this.path, required this.language});
  final String path;
  final KokoroLanguage language;
}

/// Local paths to verified artifacts. No model is downloaded by the engine.
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
  });
  final Float32List samples;
  final int utteranceId;
  final bool isFinal;
  final String? text, phonemes;
  int get sampleRate => 24000;
}

/// English-only Kokoro. Native work runs on one long-lived worker isolate.
/// Web currently throws UnsupportedError rather than blocking the UI thread.
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
  }) => _speakInput(
    Stream.value(text),
    voice: voice,
    speed: speed,
    normalize: normalize,
  );

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

  KokoroTextInput input({
    required String voice,
    double speed = 1,
    bool normalize = true,
  }) {
    validateRequest(voice, speed);
    return KokoroTextInput._(this, voice, speed, normalize);
  }

  void validateRequest(String voice, double speed) {
    if (!voices.containsKey(voice)) throw ArgumentError.value(voice, 'voice');
    if (!speed.isFinite || speed <= 0) {
      throw ArgumentError.value(speed, 'speed');
    }
  }

  Stream<KokoroChunk> _speakInput(
    Stream<String?> input, {
    required String voice,
    required double speed,
    required bool normalize,
  }) async* {
    validateRequest(voice, speed);
    var buffer = '';
    await for (final text in input) {
      if (text != null) buffer += text;
      final split = kokoroSplitSentences(buffer, finalInput: text == null);
      buffer = split.remainder;
      if (buffer.length > 65536) {
        throw StateError('Unterminated input exceeds 64K characters; flush it');
      }
      for (final unit in split.units) {
        yield* renderUtterance(
          unit,
          voice: voice,
          speed: speed,
          normalize: normalize,
        );
      }
    }
    for (final unit in kokoroSplitSentences(buffer, finalInput: true).units) {
      yield* renderUtterance(
        unit,
        voice: voice,
        speed: speed,
        normalize: normalize,
      );
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
/// There is a 64K pending-character limit; add throws rather than buffering
/// unlimited LLM output while the audio consumer is paused.
class KokoroTextInput {
  KokoroTextInput._(Kokoro engine, String voice, double speed, bool normalize) {
    _controller = StreamController<String?>(
      onCancel: () {
        _cancelled = true;
      },
    );
    final drained = _controller.stream.map((text) {
      _pending -= text?.length ?? 0;
      _events--;
      return text;
    });
    audio = engine._speakInput(
      drained,
      voice: voice,
      speed: speed,
      normalize: normalize,
    );
  }
  late final StreamController<String?> _controller;
  late final Stream<KokoroChunk> audio;
  int _pending = 0, _events = 0;
  bool _closed = false, _cancelled = false;
  void _checkOpen() {
    if (_closed || _cancelled) throw StateError('Kokoro text input is closed');
    if (_events >= 1024) throw StateError('Too many pending text events');
  }

  void add(String text) {
    _checkOpen();
    if (_pending + text.length > 65536) {
      throw StateError('Pending text exceeds 64K characters');
    }
    _events++;
    _pending += text.length;
    _controller.add(text);
  }

  void flush() {
    _checkOpen();
    _events++;
    _controller.add(null);
  }

  /// Ends the text. Pending text is still spoken. Completes at once; the
  /// [audio] stream ends after the last chunk. Closing again does nothing.
  Future<void> close() async {
    if (_closed || _cancelled) return;
    _closed = true;
    unawaited(_controller.close());
  }
}
