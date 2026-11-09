import 'dart:math' as math;
import 'dart:typed_data';

import '../wolf_defender.dart';
import 'wolf_defender_tokenizer.dart';

/// The positions of one model input, with `<bos>` and `<eos>`.
const wolfDefenderWindowPositions = 2048;

/// Adjacent windows share this many tokens.
const wolfDefenderWindowOverlap = 64;

const _bos = 2;
const _eos = 1;

/// Runs the Wolf Defender graph.
abstract interface class WolfDefenderOnnxBackend {
  /// The two logits, benign and injection, of [ids]: `<bos>`, at most 2046
  /// tokens, and `<eos>`. The graph takes int64; web has no Int64List, so
  /// each backend converts.
  Future<Float32List> run(Int32List ids);

  Future<void> close();
}

final class WolfDefenderEngine {
  WolfDefenderEngine(this._backend, this._tokenizer) {
    if (_tokenizer.token(_bos) != '<bos>' ||
        _tokenizer.token(_eos) != '<eos>') {
      throw const FormatException('The tokenizer is not the one of the model');
    }
  }

  final WolfDefenderOnnxBackend _backend;
  final WolfDefenderTokenizer _tokenizer;

  Future<void> close() => _backend.close();

  Future<WolfDefenderResult> classify(String text) async {
    final tokens = _tokenizer.encode(text);
    final windows = wolfDefenderWindows(tokens.length);
    final logits = <Float32List>[];
    for (final (start, end) in windows) {
      final ids = Int32List(end - start + 2);
      ids[0] = _bos;
      for (var i = start; i < end; i++) {
        ids[i - start + 1] = tokens[i];
      }
      ids[ids.length - 1] = _eos;
      final values = await _backend.run(ids);
      if (values.length != 2) {
        throw StateError('Wolf Defender gave ${values.length} logits, not 2');
      }
      logits.add(values);
    }
    return WolfDefenderResult(
      injectionProbability: wolfDefenderPool(logits),
      tokens: tokens.length,
      windows: windows.length,
    );
  }
}

/// The token ranges of the windows of [tokens] tokens. Each has at most 2046
/// tokens; each after the first starts 64 tokens before the end of the one
/// before it. No tokens is one empty window.
List<(int, int)> wolfDefenderWindows(int tokens) {
  const size = wolfDefenderWindowPositions - 2;
  final windows = <(int, int)>[];
  var start = 0;
  while (true) {
    final end = math.min(start + size, tokens);
    windows.add((start, end));
    if (end == tokens) return windows;
    start = end - wolfDefenderWindowOverlap;
  }
}

/// The injection probability of the windows' [logits]: per class, a smooth
/// maximum over the windows (temperature 1 for one window, 0.1 for more),
/// normalized by the window count; then softmax. One window is the softmax of
/// its logits. Patronus's `inference.py` defines it.
double wolfDefenderPool(List<Float32List> logits) {
  if (logits.isEmpty) throw ArgumentError.value(logits, 'logits', 'empty');
  final temperature = logits.length == 1 ? 1.0 : 0.1;
  final logCount = math.log(logits.length);
  final pooled = List<double>.filled(2, 0);
  for (var c = 0; c < 2; c++) {
    var maximum = double.negativeInfinity;
    for (final window in logits) {
      maximum = math.max(maximum, window[c]);
    }
    var sum = 0.0;
    for (final window in logits) {
      sum += math.exp((window[c] - maximum) / temperature);
    }
    pooled[c] = maximum + temperature * (math.log(sum) - logCount);
  }
  // Softmax of two values: the probability of class 1.
  return 1 / (1 + math.exp(pooled[0] - pooled[1]));
}
