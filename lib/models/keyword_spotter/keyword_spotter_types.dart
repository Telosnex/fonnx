import 'dart:typed_data';

/// Identity of the exact token-ID-to-piece mapping used by the English model.
///
/// Persist this beside token IDs. A sequence may only be reused when its
/// identity matches [keywordSpotterTokenizerId]. The suffix is a SHA-256 of
/// the 500 vocabulary pieces joined by a NUL byte, in token-ID order.
const keywordSpotterTokenizerId =
    'gigaspeech3m-en-bpe500:'
    'b38b12916722c11272652064fbff4e67b931cbdcd989fc20ea6a3c734415bcba';

const keywordSpotterVocabularySize = 500;

final class KeywordSpotterBundle {
  const KeywordSpotterBundle({
    required this.encoderPath,
    required this.decoderPath,
    required this.joinerPath,
  });

  factory KeywordSpotterBundle.gigaSpeech3m(String directory) {
    final separator = directory.endsWith('/') ? '' : '/';
    final prefix = '$directory$separator';
    return KeywordSpotterBundle(
      encoderPath: '${prefix}encoder-epoch-12-avg-2-chunk-16-left-64.int8.onnx',
      decoderPath: '${prefix}decoder-epoch-12-avg-2-chunk-16-left-64.int8.onnx',
      joinerPath: '${prefix}joiner-epoch-12-avg-2-chunk-16-left-64.int8.onnx',
    );
  }

  final String encoderPath;
  final String decoderPath;
  final String joinerPath;
}

/// An exact decoder token sequence and the vocabulary that gives it meaning.
final class KeywordTokenSequence {
  const KeywordTokenSequence({
    required this.tokenizerId,
    required this.tokenIds,
  });

  final String tokenizerId;
  final List<int> tokenIds;
}

/// Text and exact decoder output from pronunciation discovery.
final class KeywordTranscription {
  KeywordTranscription({
    required this.text,
    required this.tokenizerId,
    required Iterable<int> tokenIds,
  }) : tokenIds = List<int>.unmodifiable(tokenIds);

  final String text;
  final String tokenizerId;
  final List<int> tokenIds;

  KeywordTokenSequence get tokenSequence =>
      KeywordTokenSequence(tokenizerId: tokenizerId, tokenIds: tokenIds);
}

final class KeywordPhrase {
  const KeywordPhrase(
    this.text, {
    this.spokenForms = const <String>[],
    this.spokenTokenSequences = const <KeywordTokenSequence>[],
    this.score = 1,
    this.threshold = 0.25,
  });

  /// Text returned in [KeywordDetection.phrase].
  final String text;

  /// Alternative acoustic spellings that match the same phrase.
  ///
  /// This is useful for names and brands whose written form is tokenized
  /// differently from how the model hears them. For example:
  ///
  /// ```dart
  /// KeywordPhrase('telosnex', spokenForms: ['tell us next'])
  /// ```
  final List<String> spokenForms;

  /// Exact acoustic tokenizations that match the same phrase.
  ///
  /// These avoid the potentially lossy decode-to-text/re-encode round trip.
  /// Persist [KeywordTranscription.tokenizerId] with the IDs and only supply a
  /// sequence when it matches [keywordSpotterTokenizerId]. Keep the decoded
  /// [spokenForms] as a portable fallback when the vocabulary changes.
  final List<KeywordTokenSequence> spokenTokenSequences;

  final double score;
  final double threshold;
}

final class KeywordDetection {
  const KeywordDetection({
    required this.phrase,
    required this.detectedAt,
    required this.tokenTimestamps,
    required this.meanTokenProbability,
  });

  final String phrase;
  final Duration detectedAt;
  final List<Duration> tokenTimestamps;
  final double meanTokenProbability;

  Duration get startTime => tokenTimestamps.first;

  Duration get endTime =>
      tokenTimestamps.last + const Duration(milliseconds: 40);
}

/// Validates and snapshots caller-owned phrase configuration at API entry.
///
/// Inference is serialized asynchronously, so retaining either the outer list
/// or mutable pronunciation/token lists would make results depend on
/// mutations performed after the call returned.
List<KeywordPhrase> validatedKeywordPhraseSnapshot(
  Iterable<KeywordPhrase> keywords,
) {
  final result = <KeywordPhrase>[];
  for (final keyword in keywords) {
    if (keyword.text.trim().isEmpty) {
      throw ArgumentError.value(
        keyword.text,
        'KeywordPhrase.text',
        'Must not be empty',
      );
    }
    if (!keyword.score.isFinite || keyword.score <= 0) {
      throw ArgumentError.value(
        keyword.score,
        'KeywordPhrase.score',
        'Must be finite and > 0',
      );
    }
    if (!keyword.threshold.isFinite ||
        keyword.threshold <= 0 ||
        keyword.threshold > 1) {
      throw ArgumentError.value(
        keyword.threshold,
        'KeywordPhrase.threshold',
        'Must be finite and in (0, 1]',
      );
    }
    final tokenSequences = <KeywordTokenSequence>[];
    for (final sequence in keyword.spokenTokenSequences) {
      if (sequence.tokenizerId != keywordSpotterTokenizerId) {
        throw ArgumentError.value(
          sequence.tokenizerId,
          'KeywordTokenSequence.tokenizerId',
          'Does not match the active keyword-spotter vocabulary',
        );
      }
      if (sequence.tokenIds.isEmpty ||
          sequence.tokenIds.any(
            (id) => id < 3 || id >= keywordSpotterVocabularySize,
          )) {
        throw ArgumentError.value(
          sequence.tokenIds,
          'KeywordTokenSequence.tokenIds',
          'Must contain only normal vocabulary token IDs',
        );
      }
      tokenSequences.add(
        KeywordTokenSequence(
          tokenizerId: sequence.tokenizerId,
          tokenIds: List<int>.unmodifiable(sequence.tokenIds),
        ),
      );
    }
    result.add(
      KeywordPhrase(
        keyword.text,
        spokenForms: List<String>.unmodifiable(keyword.spokenForms),
        spokenTokenSequences: List<KeywordTokenSequence>.unmodifiable(
          tokenSequences,
        ),
        score: keyword.score,
        threshold: keyword.threshold,
      ),
    );
  }
  if (result.isEmpty) {
    throw ArgumentError.value(keywords, 'keywords', 'Must not be empty');
  }
  return List<KeywordPhrase>.unmodifiable(result);
}

abstract interface class KwsOnnxBackend {
  Future<KwsEncoderOutput> runEncoder(Float32List features);

  Future<Float32List> runDecoder(Int64List tokenContexts);

  Future<Float32List> runJoiner(
    Float32List encoderVectors,
    Float32List decoderVectors,
  );

  Future<void> resetEncoderState();

  Future<void> close();
}

final class KwsEncoderOutput {
  const KwsEncoderOutput({required this.values, required this.frameCount});

  final Float32List values;
  final int frameCount;
}
