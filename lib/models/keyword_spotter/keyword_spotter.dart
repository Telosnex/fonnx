import 'dart:typed_data';

import 'keyword_spotter_none.dart'
    if (dart.library.io) 'keyword_spotter_native.dart'
    if (dart.library.js_interop) 'keyword_spotter_web.dart';
import 'keyword_spotter_types.dart';

export 'keyword_spotter_types.dart';

abstract class KeywordSpotter {
  static Future<KeywordSpotter> load({
    required KeywordSpotterBundle bundle,
    required List<KeywordPhrase> keywords,
    int maxActivePaths = 4,
    int trailingBlankFrames = 1,
  }) => getKeywordSpotter(
    bundle: bundle,
    keywords: keywords,
    maxActivePaths: maxActivePaths,
    trailingBlankFrames: trailingBlankFrames,
  );

  Stream<KeywordDetection> get detections;

  /// Accept normalized mono samples. English KWS currently requires 16 kHz.
  Future<void> acceptSamples(Float32List samples, {int sampleRate = 16000});

  Future<void> acceptPcm16(Uint8List bytes, {int sampleRate = 16000}) =>
      acceptSamples(_pcm16ToSamples(bytes), sampleRate: sampleRate);

  /// Transcribes [samples] to the closest English text the model heard.
  ///
  /// Use this to discover [KeywordPhrase.spokenForms] for names and brands:
  /// record the user saying the word, and use the returned text as an alias.
  /// Resets streaming detection state.
  Future<String> transcribeSamples(
    Float32List samples, {
    int sampleRate = 16000,
  });

  Future<String> transcribePcm16(Uint8List bytes, {int sampleRate = 16000}) =>
      transcribeSamples(_pcm16ToSamples(bytes), sampleRate: sampleRate);

  static Float32List _pcm16ToSamples(Uint8List bytes) {
    if (bytes.length.isOdd) {
      throw ArgumentError.value(bytes.length, 'bytes.length', 'Must be even');
    }
    final data = ByteData.sublistView(bytes);
    final samples = Float32List(bytes.length ~/ 2);
    for (var i = 0; i < samples.length; i++) {
      samples[i] = data.getInt16(i * 2, Endian.little) / 32768;
    }
    return samples;
  }

  /// Flush the final partial feature frames and trailing-blank confirmation.
  Future<void> finish();

  /// Atomically replaces all phrases and resets decoder context.
  Future<void> setKeywords(List<KeywordPhrase> keywords);

  Future<void> reset();

  Future<void> close();
}
