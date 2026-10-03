import 'dart:typed_data';

/// Encoder/decoder time steps per swipe.
const futoSwipeTimeSteps = 32;

/// Refined decoder classes: `a` through `z`, then blank.
const futoSwipeClassCount = 27;

/// Index of the CTC blank class in [FutoSwipeEmissions].
const futoSwipeBlankIndex = 26;

/// Samples per coordinate after trace resampling.
const futoSwipeTraceSamples = 64;

/// Key slots reserved by the encoder. English QWERTY uses the first 26.
const futoSwipeMaxKeys = 64;

/// Words of preceding context consumed by ContextLM.
const futoContextLength = 16;

/// ContextLM state and embedding width.
const futoContextDimension = 16;

/// Rows in each ContextLM embedding table. Token ID 0 is padding.
const futoContextVocabularySize = 32768;

/// Token ID that selects the hashed-word path in ContextLM.
const futoContextHashedTokenId = 32768;

/// File locations of the converted FUTO Swipe compatibility unit.
///
/// The encoder, decoder, ContextLM, embeddings, vocabulary, and scoring
/// configuration were released together. Do not mix files across revisions.
final class FutoSwipeBundle {
  const FutoSwipeBundle({
    required this.encoderPath,
    required this.decoderPath,
    required this.contextModelPath,
    required this.embeddingsPath,
    required this.vocabularyPath,
    required this.scoringPath,
  });

  /// Uses the directory layout produced by `tool/futo/convert.dart`.
  factory FutoSwipeBundle.fromDirectory(String directory) {
    final separator = directory.endsWith('/') ? '' : '/';
    final prefix = '$directory$separator';
    return FutoSwipeBundle(
      encoderPath: '${prefix}honorable_sturgeon/model_fp32.onnx',
      decoderPath: '${prefix}magic_macaw/model_fp32.onnx',
      contextModelPath: '${prefix}hungry_jellyfish/context_lm.onnx',
      embeddingsPath: '${prefix}hungry_jellyfish/get_embeddings.onnx',
      vocabularyPath: '${prefix}hungry_jellyfish/vocab.txt',
      scoringPath: '${prefix}scoring.json',
    );
  }

  final String encoderPath;
  final String decoderPath;
  final String contextModelPath;
  final String embeddingsPath;
  final String vocabularyPath;
  final String scoringPath;

  List<String> get paths => [
    encoderPath,
    decoderPath,
    contextModelPath,
    embeddingsPath,
    vocabularyPath,
    scoringPath,
  ];
}

/// One touch sample in letter-panel coordinates.
///
/// `x` is 0 at the left edge and 1 at the right edge of the letter panel.
/// `y` is 0 at the top of the first letter row and 1 at the bottom of the
/// third. Exclude the suggestion strip and the space-bar row.
final class FutoSwipePoint {
  const FutoSwipePoint(this.x, this.y, this.time);

  final double x;
  final double y;

  /// Any monotonic clock. Only differences between samples are used.
  final Duration time;
}

/// Centers of the 26 English letter keys in letter-panel coordinates.
///
/// The paired decoder is specific to English QWERTY. Supply the rendered key
/// centers of a QWERTY panel, not a different letter arrangement.
final class FutoSwipeLayout {
  FutoSwipeLayout(Map<String, (double, double)> keyCenters)
    : keyCenters = Map<String, (double, double)>.unmodifiable(keyCenters) {
    if (keyCenters.length != 26) {
      throw ArgumentError.value(
        keyCenters.keys.toList(),
        'keyCenters',
        'Must contain exactly the letters a-z',
      );
    }
    for (var i = 0; i < 26; i++) {
      final letter = String.fromCharCode(97 + i);
      final center = keyCenters[letter];
      if (center == null) {
        throw ArgumentError.value(
          keyCenters.keys.toList(),
          'keyCenters',
          'Missing letter "$letter"',
        );
      }
      if (!center.$1.isFinite || !center.$2.isFinite) {
        throw ArgumentError.value(
          center,
          'keyCenters[$letter]',
          'Must be finite',
        );
      }
    }
  }

  /// Uniform QWERTY geometry used for the published validation.
  ///
  /// Rows start at x = 0.05, 0.10, and 0.20 with 0.1 key spacing. Row centers
  /// are at 1/6, 1/2, and 5/6 of the letter-panel height.
  factory FutoSwipeLayout.englishQwerty() => _englishQwerty;

  static final _englishQwerty = () {
    const rows = ['qwertyuiop', 'asdfghjkl', 'zxcvbnm'];
    const starts = [0.05, 0.10, 0.20];
    return FutoSwipeLayout({
      for (var row = 0; row < rows.length; row++)
        for (var col = 0; col < rows[row].length; col++)
          rows[row][col]: (starts[row] + col * 0.1, (row + 0.5) / 3),
    });
  }();

  final Map<String, (double, double)> keyCenters;

  /// Encoder `layout_keys` input, `[64, 2]` row-major, keys `a`-`z` first.
  Float32List toKeyTensor() {
    final result = Float32List(futoSwipeMaxKeys * 2);
    for (var i = 0; i < 26; i++) {
      final center = keyCenters[String.fromCharCode(97 + i)]!;
      result[i * 2] = center.$1;
      result[i * 2 + 1] = center.$2;
    }
    return result;
  }

  /// Encoder `layout_mask` input, `[64]`, true for the 26 letters.
  Uint8List toMaskTensor() => Uint8List(futoSwipeMaxKeys)..fillRange(0, 26, 1);
}

/// A word that swipe decoding may return.
///
/// [text] is the display spelling. Its search key is lowercase `a`-`z` with
/// apostrophes removed, so `don't` matches a `dont` swipe. Entries with other
/// characters after that step are not swipeable and are skipped.
final class FutoSwipeWord {
  const FutoSwipeWord(this.text, {this.frequency = 0});

  final String text;

  /// AOSP-style frequency value (0-255), as used by the bundle's scoring
  /// configuration. Use 0 when no frequency is known.
  final int frequency;
}

/// A ranked swipe result.
final class FutoSwipeCandidate {
  FutoSwipeCandidate({
    required this.word,
    required this.searchKey,
    required Iterable<String> alternatives,
    required this.score,
  }) : alternatives = List<String>.unmodifiable(alternatives);

  /// Best-scoring display spelling for [searchKey].
  final String word;

  /// Lowercase letters that the CTC search matched.
  final String searchKey;

  /// Other lexicon spellings that share [searchKey], best first.
  final List<String> alternatives;

  /// Combined natural-log score. Higher is better. Not a probability.
  final double score;
}

/// A ContextLM word score.
final class FutoWordScore {
  const FutoWordScore(this.word, this.score);

  final String word;

  /// Unnormalized log score: embedding dot product plus bias.
  final double score;
}

/// Refined per-step log scores from the English decoder.
final class FutoSwipeEmissions {
  FutoSwipeEmissions(this.logScores) {
    if (logScores.length != futoSwipeTimeSteps * futoSwipeClassCount) {
      throw ArgumentError.value(logScores.length, 'logScores.length');
    }
  }

  /// Row-major `[32, 27]`. Classes are `a`-`z`, then blank (index 26).
  final Float32List logScores;

  double at(int step, int classIndex) =>
      logScores[step * futoSwipeClassCount + classIndex];
}

/// ContextLM output tables, copied once from `get_embeddings.onnx`.
final class FutoContextEmbeddings {
  FutoContextEmbeddings({
    required this.exactEmbeddings,
    required this.exactBiases,
    required this.hashedEmbeddings,
    required this.hashedBiases,
  }) {
    const rows = futoContextVocabularySize;
    const width = futoContextDimension;
    if (exactEmbeddings.length != rows * width ||
        hashedEmbeddings.length != rows * width ||
        exactBiases.length != rows ||
        hashedBiases.length != rows) {
      throw ArgumentError('Unexpected ContextLM embedding table sizes');
    }
  }

  final Float32List exactEmbeddings;
  final Float32List exactBiases;
  final Float32List hashedEmbeddings;
  final Float32List hashedBiases;
}

/// Raw encoder outputs for one swipe.
final class FutoEncoderOutput {
  FutoEncoderOutput({
    required this.logEmissions,
    required this.coefficients,
    required this.intention,
  }) {
    if (logEmissions.length != futoSwipeTimeSteps * 65 ||
        coefficients.length != futoSwipeTimeSteps * 64 ||
        intention.length != futoSwipeTimeSteps) {
      throw StateError('Unexpected FUTO encoder output sizes');
    }
  }

  /// `[32, 65]`: 64 key slots, then blank.
  final Float32List logEmissions;

  /// `[32, 64]`.
  final Float32List coefficients;

  /// `[32]`.
  final Float32List intention;
}

/// Platform inference boundary. Implementations own their sessions.
abstract interface class FutoSwipeOnnxBackend {
  Future<FutoEncoderOutput> runEncoder(
    Float32List features,
    Float32List layoutKeys,
    Uint8List layoutMask,
  );

  /// Input `[32, 92]`; output `[32, 27]`.
  Future<Float32List> runDecoder(Float32List features);

  /// Inputs `[16]` IDs and `[16, 2]` hash buckets; output `[16, 16]`.
  ///
  /// The graph takes int64. Values fit in 16 bits, and `Int64List` is
  /// unavailable on the Web, so backends widen at the ONNX boundary.
  Future<Float32List> runContext(Int32List tokenIds, Int32List hashBuckets);

  Future<FutoContextEmbeddings> loadEmbeddings();

  Future<void> close();
}

/// Validates and snapshots caller-owned trace data at API entry.
List<FutoSwipePoint> validatedFutoTrace(Iterable<FutoSwipePoint> trace) {
  final result = List<FutoSwipePoint>.unmodifiable(trace);
  if (result.isEmpty) {
    throw ArgumentError.value(trace, 'trace', 'Must not be empty');
  }
  for (var i = 0; i < result.length; i++) {
    final point = result[i];
    if (!point.x.isFinite || !point.y.isFinite) {
      throw ArgumentError.value(
        (point.x, point.y),
        'trace[$i]',
        'Coordinates must be finite',
      );
    }
    if (i > 0 && point.time < result[i - 1].time) {
      throw ArgumentError.value(
        point.time,
        'trace[$i].time',
        'Timestamps must not decrease',
      );
    }
  }
  return result;
}

/// Validates and snapshots a caller-owned lexicon at API entry.
List<FutoSwipeWord> validatedFutoLexicon(Iterable<FutoSwipeWord> lexicon) {
  final result = <FutoSwipeWord>[];
  for (final word in lexicon) {
    if (word.text.trim().isEmpty) {
      throw ArgumentError.value(word.text, 'FutoSwipeWord.text', 'Empty');
    }
    if (word.frequency < 0 || word.frequency > 255) {
      throw ArgumentError.value(
        word.frequency,
        'FutoSwipeWord.frequency',
        'Must be 0..255',
      );
    }
    result.add(FutoSwipeWord(word.text, frequency: word.frequency));
  }
  return List<FutoSwipeWord>.unmodifiable(result);
}

/// Snapshots caller-owned context words.
List<String> validatedFutoWords(Iterable<String> words, String name) {
  final result = List<String>.unmodifiable(words);
  for (var i = 0; i < result.length; i++) {
    if (result[i].isEmpty) {
      throw ArgumentError.value(result[i], '$name[$i]', 'Must not be empty');
    }
  }
  return result;
}
