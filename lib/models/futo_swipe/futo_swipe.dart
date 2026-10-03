import 'futo_swipe_none.dart'
    if (dart.library.io) 'futo_swipe_native.dart'
    if (dart.library.js_interop) 'futo_swipe_web.dart';
import 'futo_swipe_types.dart';

export 'futo_swipe_types.dart';

/// English QWERTY swipe typing and word context from FUTO Swipe models.
///
/// The bundle's weights are subject to the FUTO Model Weights License 1.0.
/// Products using them must display visible "FUTO Swipe" attribution.
abstract class FutoSwipe {
  /// Loads the encoder, decoder, and ContextLM, and builds the swipe lexicon.
  ///
  /// With [includeModelVocabulary], the 32,768 ContextLM vocabulary words are
  /// swipeable before [lexicon] is added. [beamWidth] bounds the CTC search;
  /// the published validation used 300.
  static Future<FutoSwipe> load({
    required FutoSwipeBundle bundle,
    Iterable<FutoSwipeWord> lexicon = const [],
    bool includeModelVocabulary = true,
    int beamWidth = 300,
  }) {
    if (bundle.paths.any((path) => path.trim().isEmpty)) {
      throw ArgumentError.value(bundle, 'bundle', 'Paths must not be empty');
    }
    if (beamWidth < 1 || beamWidth > 5000) {
      throw ArgumentError.value(beamWidth, 'beamWidth', 'Must be 1..5000');
    }
    return getFutoSwipe(
      bundle: bundle,
      lexicon: validatedFutoLexicon(lexicon),
      includeModelVocabulary: includeModelVocabulary,
      beamWidth: beamWidth,
    );
  }

  /// Swipeable lexicon spellings after the most recent load or [setLexicon].
  int get lexiconSize;

  /// Ranks lexicon words for a swipe [trace].
  ///
  /// [previousWords] are the preceding words, oldest first; ContextLM reads
  /// the last 16. Null disables ContextLM. An empty list scores the word as
  /// the start of text. Each configuration uses its matching bundle weights.
  Future<List<FutoSwipeCandidate>> decode(
    Iterable<FutoSwipePoint> trace, {
    FutoSwipeLayout? layout,
    Iterable<String>? previousWords,
    int maxCandidates = 3,
  });

  /// Refined decoder log scores for [trace], before lexicon search.
  Future<FutoSwipeEmissions> emissions(
    Iterable<FutoSwipePoint> trace, {
    FutoSwipeLayout? layout,
  });

  /// ContextLM scores for each of [words] following [previousWords].
  ///
  /// Use these to rank tap-correction candidates. Scores are unnormalized and
  /// comparable only within one context.
  Future<List<double>> scoreWords(
    Iterable<String> previousWords,
    Iterable<String> words,
  );

  /// The [count] highest-scoring exact-vocabulary words after
  /// [previousWords]. The model is small; treat results as suggestions.
  Future<List<FutoWordScore>> predictNextWords(
    Iterable<String> previousWords, {
    int count = 5,
  });

  /// Atomically replaces the swipe lexicon. Returns the swipeable count.
  Future<int> setLexicon(
    Iterable<FutoSwipeWord> lexicon, {
    bool includeModelVocabulary = true,
  });

  Future<void> close();
}

/// Shared argument checks for platform implementations.
int validatedFutoCount(int value, String name) {
  if (value < 1 || value > 1000) {
    throw ArgumentError.value(value, name, 'Must be 1..1000');
  }
  return value;
}
