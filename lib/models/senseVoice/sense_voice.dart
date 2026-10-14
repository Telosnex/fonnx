import 'dart:typed_data';

import 'sense_voice_none.dart'
    if (dart.library.io) 'sense_voice_native.dart'
    if (dart.library.js_interop) 'sense_voice_web.dart';

import 'src/sense_voice_features.dart';

/// The longest audio that [SenseVoice] transcribes: 60 seconds.
const senseVoiceMaxSamples = 60 * senseVoiceSampleRate;

/// The languages of SenseVoice Small, with their model IDs.
enum SenseVoiceLanguage {
  /// The model detects the language.
  auto(0),
  mandarin(3),
  english(4),
  cantonese(7),
  japanese(11),
  korean(12);

  const SenseVoiceLanguage(this.id);

  /// The value of the model input `language`.
  final int id;
}

/// The files of SenseVoice Small: the int8 sherpa-onnx export of
/// FunAudioLLM/SenseVoiceSmall, and its tokens.
final class SenseVoiceBundle {
  const SenseVoiceBundle({required this.modelPath, required this.tokensPath});

  /// `sense_voice_small_int8.onnx` and `sense_voice_small_tokens.txt` in
  /// [directory]. On web, [directory] is a URL.
  factory SenseVoiceBundle.inDirectory(String directory) {
    final base = '$directory${directory.endsWith('/') ? '' : '/'}';
    return SenseVoiceBundle(
      modelPath: '${base}sense_voice_small_int8.onnx',
      tokensPath: '${base}sense_voice_small_tokens.txt',
    );
  }

  final String modelPath;

  /// `tokens.txt`: one token and its ID per line.
  final String tokensPath;

  @override
  bool operator ==(Object other) =>
      other is SenseVoiceBundle &&
      other.modelPath == modelPath &&
      other.tokensPath == tokensPath;

  @override
  int get hashCode => Object.hash(modelPath, tokensPath);

  @override
  String toString() => 'SenseVoiceBundle($modelPath, $tokensPath)';
}

/// Speech-to-text with Alibaba's SenseVoice Small: Mandarin, Cantonese,
/// English, Japanese and Korean. One model run and greedy CTC.
abstract class SenseVoice {
  static SenseVoice? _instance;

  SenseVoiceBundle get bundle;

  /// Returns the one instance. It loads the model on first use.
  static SenseVoice load(SenseVoiceBundle bundle) {
    if (bundle.modelPath.trim().isEmpty || bundle.tokensPath.trim().isEmpty) {
      throw ArgumentError.value(bundle, 'bundle', 'Paths must not be empty');
    }
    final current = _instance;
    if (current != null && current.bundle != bundle) {
      throw StateError('SenseVoice is already loaded from ${current.bundle}');
    }
    return _instance ??= getSenseVoice(bundle);
  }

  /// Transcribes [bytes]: 16-bit little-endian PCM, mono, 16 kHz, at most
  /// 60 seconds. The text has punctuation, and numbers as digits.
  ///
  /// Audio without speech, even digital silence, often gives a short false
  /// transcript such as "그." Run a voice activity detector first.
  Future<String> doInference(
    Uint8List bytes, {
    SenseVoiceLanguage language = SenseVoiceLanguage.auto,
  });
}
