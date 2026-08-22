import 'dart:typed_data';

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

final class KeywordPhrase {
  const KeywordPhrase(
    this.text, {
    this.spokenForms = const <String>[],
    this.score = 1,
    this.threshold = 0.25,
  }) : assert(score > 0),
       assert(threshold > 0 && threshold <= 1);

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
