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
    final starts = <int>[];
    final tokens = _tokenizer.encode(text, starts: starts);
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
      windowScores: [
        for (var w = 0; w < windows.length; w++)
          WolfDefenderWindowScore(
            benignLogit: logits[w][0],
            injectionLogit: logits[w][1],
            start: wolfDefenderWindowStart(starts, windows[w].$1, text.length),
            end: wolfDefenderWindowEnd(starts, windows[w].$2, text.length),
          ),
      ],
    );
  }
}

/// The text offset where the window that starts at token [token] starts:
/// the start of the word of that token. [starts] holds the word offset of
/// each token, as [WolfDefenderTokenizer.encode] gives it.
int wolfDefenderWindowStart(List<int> starts, int token, int textLength) =>
    token < starts.length ? starts[token] : textLength;

/// The text offset where the window that ends before token [token] ends:
/// the end of the word of its last token. A window can end inside a word;
/// its text then includes the whole word.
int wolfDefenderWindowEnd(List<int> starts, int token, int textLength) {
  if (token <= 0) return 0;
  final last = starts[token - 1];
  for (var k = token; k < starts.length; k++) {
    if (starts[k] > last) return starts[k];
  }
  return textLength;
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
