import 'dart:typed_data';

import 'keyword_spotter_none.dart'
    if (dart.library.io) 'keyword_spotter_native.dart'
    if (dart.library.js_interop) 'keyword_spotter_web.dart';
import 'keyword_spotter_types.dart';
import 'src/english_tokenizer.dart';

export 'keyword_spotter_types.dart';

abstract class KeywordSpotter {
  static final EnglishKwsTokenizer _tokenizer = EnglishKwsTokenizer();

  /// Vocabulary identity for token IDs accepted and returned by this API.
  static const tokenizerId = keywordSpotterTokenizerId;

  /// Decodes exact token IDs without running the unigram encoder again.
  static String decodeTokenIds(Iterable<int> tokenIds) =>
      _tokenizer.decode(tokenIds);

  static Future<KeywordSpotter> load({
    required KeywordSpotterBundle bundle,
    required List<KeywordPhrase> keywords,
    int maxActivePaths = 4,
    int trailingBlankFrames = 1,
  }) {
    if ([
      bundle.encoderPath,
      bundle.decoderPath,
      bundle.joinerPath,
    ].any((path) => path.trim().isEmpty)) {
      throw ArgumentError.value(
        bundle,
        'bundle',
        'Model paths must not be empty',
      );
    }
    if (maxActivePaths < 1 || maxActivePaths > 64) {
      throw ArgumentError.value(
        maxActivePaths,
        'maxActivePaths',
        'Must be 1..64',
      );
    }
    if (trailingBlankFrames < 0 || trailingBlankFrames > 100) {
      throw ArgumentError.value(
        trailingBlankFrames,
        'trailingBlankFrames',
        'Must be 0..100',
      );
    }
    return getKeywordSpotter(
      bundle: bundle,
      keywords: validatedKeywordPhraseSnapshot(keywords),
      maxActivePaths: maxActivePaths,
      trailingBlankFrames: trailingBlankFrames,
    );
  }

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
  }) async =>
      (await transcribeSamplesWithTokens(samples, sampleRate: sampleRate)).text;

  /// Transcribes audio and preserves the model's exact decoder token IDs.
  ///
  /// [KeywordTranscription.text] is [decodeTokenIds] applied to those IDs.
  /// Keep the text as a portable fallback and use the IDs only while
  /// [KeywordTranscription.tokenizerId] equals [tokenizerId].
  Future<KeywordTranscription> transcribeSamplesWithTokens(
    Float32List samples, {
    int sampleRate = 16000,
  });

  Future<String> transcribePcm16(Uint8List bytes, {int sampleRate = 16000}) =>
      transcribeSamples(_pcm16ToSamples(bytes), sampleRate: sampleRate);

  Future<KeywordTranscription> transcribePcm16WithTokens(
    Uint8List bytes, {
    int sampleRate = 16000,
  }) => transcribeSamplesWithTokens(
    _pcm16ToSamples(bytes),
    sampleRate: sampleRate,
  );

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
