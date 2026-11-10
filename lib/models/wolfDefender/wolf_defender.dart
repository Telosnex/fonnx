import 'dart:math' as math;

import 'wolf_defender_none.dart'
    if (dart.library.io) 'wolf_defender_native.dart'
    if (dart.library.js_interop) 'wolf_defender_web.dart';

/// The files of Wolf Defender Edge: one model and the tokenizer.
final class WolfDefenderBundle {
  const WolfDefenderBundle({
    required this.modelPath,
    required this.tokenizerPath,
  });

  /// [wolfDefenderModelFileName] and [wolfDefenderTokenizerFileName] in
  /// [directory]. On web, [directory] is a URL.
  factory WolfDefenderBundle.inDirectory(String directory) {
    final base = '$directory${directory.endsWith('/') ? '' : '/'}';
    return WolfDefenderBundle(
      modelPath: '$base$wolfDefenderModelFileName',
      tokenizerPath: '$base$wolfDefenderTokenizerFileName',
    );
  }

  final String modelPath;
  final String tokenizerPath;

  @override
  bool operator ==(Object other) =>
      other is WolfDefenderBundle &&
      other.modelPath == modelPath &&
      other.tokenizerPath == tokenizerPath;

  @override
  int get hashCode => Object.hash(modelPath, tokenizerPath);

  @override
  String toString() => 'WolfDefenderBundle($modelPath, $tokenizerPath)';
}

/// Patronus's `int8_int4_embeddings_x86_weight_only` file: int8 weights, an
/// int4 embedding table, and float activations. Its decisions match fp32 on
/// every CPU that fonnx tested. Patronus's other 58 MB file, with dynamic
/// int8 activations, does not: on x86 and WebAssembly, 94% matched, and it
/// reversed a reference decision on the ARM CPUs of CI.
const wolfDefenderModelFileName = 'wolf_defender_edge_int8_weights.onnx';

const wolfDefenderTokenizerFileName = 'wolf_defender_edge_tokenizer.bin';

/// The model's output for one window of a text.
final class WolfDefenderWindowScore {
  const WolfDefenderWindowScore({
    required this.benignLogit,
    required this.injectionLogit,
    required this.start,
    required this.end,
  });

  final double benignLogit;
  final double injectionLogit;

  /// The UTF-16 range of the window in the text: `text.substring(start,
  /// end)`. It is extended to whole words, so adjacent windows overlap by
  /// their 64 shared tokens and up to one word more.
  final int start;
  final int end;

  /// The probability of this window alone: the softmax of its logits.
  double get injectionProbability =>
      1 / (1 + math.exp(benignLogit - injectionLogit));

  @override
  String toString() =>
      'WolfDefenderWindowScore(${injectionProbability.toStringAsFixed(6)}, '
      '$start-$end)';
}

/// The classification of one text.
final class WolfDefenderResult {
  const WolfDefenderResult({
    required this.injectionProbability,
    required this.tokens,
    required this.windows,
    this.windowScores = const [],
  });

  /// The probability, 0 to 1, that the text contains a prompt injection or
  /// a jailbreak.
  final double injectionProbability;

  /// Patronus's threshold: a probability greater than 0.5.
  bool get isInjection => injectionProbability > 0.5;

  /// The token count of the text.
  final int tokens;

  /// The model runs: one per 2046 tokens, with an overlap of 64.
  final int windows;

  /// The output of each window, in text order. [injectionProbability]
  /// combines them. Its length is [windows].
  final List<WolfDefenderWindowScore> windowScores;

  @override
  String toString() =>
      'WolfDefenderResult(${injectionProbability.toStringAsFixed(6)}, '
      '$tokens tokens, $windows windows)';
}

/// Detects prompt injections and jailbreaks in text with Patronus's Wolf
/// Defender Edge (80M parameters, Apache 2.0): for example in email,
/// documents, web pages, and tool results before an AI model reads them.
///
/// The text has no length limit. Each 2046 tokens is one model run, and the
/// results combine. The model was trained mainly on English and German.
abstract class WolfDefender {
  static WolfDefender? _instance;

  WolfDefenderBundle get bundle;

  /// Returns the one instance. It loads the model on first use.
  static WolfDefender load(WolfDefenderBundle bundle) {
    if (bundle.modelPath.trim().isEmpty ||
        bundle.tokenizerPath.trim().isEmpty) {
      throw ArgumentError.value(bundle, 'bundle', 'Paths must not be empty');
    }
    final current = _instance;
    if (current != null && current.bundle != bundle) {
      throw StateError('WolfDefender is already loaded from ${current.bundle}');
    }
    return _instance ??= getWolfDefender(bundle);
  }

  Future<WolfDefenderResult> classify(String text);
}
