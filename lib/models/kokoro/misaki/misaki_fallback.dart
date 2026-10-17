/// misaki's out-of-vocabulary fallback, independent of the ORT binding:
/// PeterReid/graphemes_to_phonemes_en_us (BART, 752k params, Apache-2.0),
/// exported to ONNX as `(input_ids, decoder_input_ids) -> logits`, decoded
/// greedily.
///
/// Mirrors misaki main's `FallbackNetwork`, except decoding runs to the
/// model's 64-position limit instead of transformers' default of 20 tokens,
/// which truncates long words.
library;

import 'dart:convert';

import 'misaki_en.dart' show MisakiPs;

final class MisakiFallbackVocab {
  MisakiFallbackVocab(String configJson) {
    final config = jsonDecode(configJson) as Map<String, dynamic>;
    final graphemes = config['grapheme_chars'] as String;
    // Python's {g: i for i, g in enumerate(...)}: later duplicates win.
    final g = graphemes.runes.toList();
    for (var i = 0; i < g.length; i++) {
      _graphemeToToken[String.fromCharCode(g[i])] = i;
    }
    _phonemes = (config['phoneme_chars'] as String).runes
        .map(String.fromCharCode)
        .toList();
    maxPositions = config['max_positions'] as int;
  }

  final Map<String, int> _graphemeToToken = {};
  late final List<String> _phonemes;
  late final int maxPositions;

  static const bos = 1, eos = 2, _unk = 3;

  /// The encoder input for [word], or null when it is too long.
  List<int>? source(String word) {
    final src = [
      bos,
      for (final r in word.runes)
        _graphemeToToken[String.fromCharCode(r)] ?? _unk,
      eos,
    ];
    return src.length > maxPositions ? null : src;
  }

  /// Whether greedy decoding of [dec] is complete. Adds the forced end token
  /// at the length limit, as transformers' forced_eos_token_id does.
  bool done(List<int> dec) {
    if (dec.last == eos && dec.length > 1) return true;
    if (dec.length >= maxPositions) return true;
    if (dec.length == maxPositions - 1) {
      dec.add(eos);
      return true;
    }
    return false;
  }

  MisakiPs phonemes(List<int> dec) {
    final out = StringBuffer();
    for (final t in dec) {
      if (t > _unk && t < _phonemes.length) out.write(_phonemes[t]);
    }
    return (out.toString(), 1);
  }

  /// Decodes [word]. [argmaxLast] returns the most likely token after [dec].
  Future<MisakiPs> decode(
    String word,
    Future<int> Function(List<int> src, List<int> dec) argmaxLast,
  ) async {
    final src = source(word);
    if (src == null) return (null, null);
    final dec = <int>[bos];
    while (!done(dec)) {
      dec.add(await argmaxLast(src, dec));
    }
    return phonemes(dec);
  }
}
