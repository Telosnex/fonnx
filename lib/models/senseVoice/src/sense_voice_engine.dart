import 'dart:typed_data';

import '../sense_voice.dart';
import 'sense_voice_features.dart';

/// Runs the SenseVoice graph.
abstract interface class SenseVoiceOnnxBackend {
  /// Returns the logits for [features], [frames] × [senseVoiceFeatureWidth]
  /// values: (frames + 4) × vocabulary.
  Future<Float32List> run(Float32List features, int frames, int language);

  Future<void> close();
}

/// The text normalization input that keeps punctuation and writes numbers as
/// digits ("withitn").
const senseVoiceWithItn = 14;

/// The CTC blank token.
const _blank = 0;

/// The first four tokens are the language, emotion, event and text
/// normalization.
const _tags = 4;

final class SenseVoiceEngine {
  SenseVoiceEngine(this._backend, this._vocabulary);

  final SenseVoiceOnnxBackend _backend;
  final List<String> _vocabulary;

  Future<void> close() => _backend.close();

  Future<String> transcribe(
    Float32List samples,
    SenseVoiceLanguage language,
  ) async {
    if (samples.length > senseVoiceMaxSamples) {
      throw ArgumentError.value(
        samples.length,
        'samples.length',
        'SenseVoice accepts at most '
            '${senseVoiceMaxSamples ~/ senseVoiceSampleRate} seconds of audio',
      );
    }
    final frames = senseVoiceFrames(samples.length);
    if (frames == 0) return '';
    final logits = await _backend.run(
      senseVoiceFeatures(samples),
      frames,
      language.id,
    );
    final tokens = greedySenseVoiceCtc(logits, _vocabulary.length);
    return decodeSenseVoiceText(
      _vocabulary,
      tokens.length > _tags ? tokens.sublist(_tags) : const [],
    );
  }
}

/// Greedy CTC: the best token of each frame, without repeats and blanks.
List<int> greedySenseVoiceCtc(Float32List logits, int vocabulary) {
  if (logits.length % vocabulary != 0) {
    throw StateError('Unexpected SenseVoice output ${logits.length}');
  }
  final tokens = <int>[];
  var previous = -1;
  for (var o = 0; o < logits.length; o += vocabulary) {
    var best = 0;
    var bestValue = logits[o];
    for (var i = 1; i < vocabulary; i++) {
      if (logits[o + i] > bestValue) {
        bestValue = logits[o + i];
        best = i;
      }
    }
    if (best != previous && best != _blank) tokens.add(best);
    previous = best;
  }
  return tokens;
}

/// Joins SentencePiece tokens: `▁` starts a word. Special tokens, such as
/// `<unk>` and `<|en|>`, are skipped.
String decodeSenseVoiceText(List<String> vocabulary, List<int> tokens) {
  final out = StringBuffer();
  for (final id in tokens) {
    final token = vocabulary[id];
    if (token.startsWith('<') && token.endsWith('>')) continue;
    out.write(token.replaceAll('▁', ' '));
  }
  return out.toString().trim();
}

/// Parses `tokens.txt`: one token and its ID per line, IDs 0, 1, 2, ...
List<String> parseSenseVoiceTokens(String text) {
  final tokens = <String>[];
  for (final line in text.split('\n')) {
    if (line.isEmpty) continue;
    final space = line.lastIndexOf(' ');
    if (space <= 0 ||
        int.tryParse(line.substring(space + 1)) != tokens.length) {
      throw FormatException('tokens.txt: line ${tokens.length + 1} is "$line"');
    }
    tokens.add(line.substring(0, space));
  }
  return tokens;
}
