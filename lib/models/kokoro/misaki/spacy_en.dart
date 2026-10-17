/// Dart port of the parts of spaCy's `en_core_web_sm` 3.8 (MIT) that misaki
/// uses: the rule-based English tokenizer and the `tok2vec` + `tagger`
/// network that predicts Penn Treebank tags.
///
/// Data comes from `tool/export_spacy_en.py`: `en_core_web_sm.json` (affix
/// regexes, special cases, norm tables, layer manifest) and
/// `en_core_web_sm_tagger.bin` (little-endian float32 weights).
///
/// Hashing uses [U64], so tags are the same on the Dart VM and on web.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'spacy_hash.dart';

/// A spaCy token: text, trailing whitespace, character offset, tag.
class SpacyToken {
  SpacyToken(this.text, {this.norm, this.spacy = false, this.idx = 0});
  final String text;

  /// Norm set by a tokenizer special case (e.g. "n't" -> "not").
  final String? norm;
  bool spacy;
  int idx;
  String tag = '';

  String get whitespace => spacy ? ' ' : '';

  @override
  String toString() => '$text/$tag';
}

final _spaceRe = RegExp(r'^\s$', unicode: true);
bool _isSpaceChar(String c) => _spaceRe.hasMatch(c);
final _allSpaceRe = RegExp(r'^\s+$', unicode: true);

class SpacyEnglish {
  SpacyEnglish._(this._config, ByteData weights)
    : _prefix = RegExp(_config['prefix'] as String, unicode: true),
      _suffix = RegExp(_config['suffix'] as String, unicode: true),
      _infix = RegExp(_config['infix'] as String, unicode: true),
      _url = RegExp(_config['url'] as String, unicode: true),
      _rules = {
        for (final MapEntry(:key, :value)
            in (_config['rules'] as Map<String, dynamic>).entries)
          key: [
            for (final t in value as List) (t[0] as String, t[1] as String?),
          ],
      },
      // Keyed by the 16-digit hex string id that the export writes.
      _lexemeNorm = (_config['lexeme_norm'] as Map).cast<String, String>(),
      _baseNorms = (_config['base_norms'] as Map).cast<String, String>(),
      _symbols = (_config['symbols'] as Map).cast<String, int>(),
      labels = (_config['labels'] as List).cast<String>() {
    _loadLayers(weights);
    for (final key in _rules.keys) {
      if (_findPrefix(key) > 0 ||
          _infix.hasMatch(key) ||
          _findSuffix(key) > 0 ||
          key.contains(' ')) {
        final seq = _tokenizeAffixes(key, withSpecialCases: false);
        (_matcher[seq.first.text] ??= []).add([for (final t in seq) t.text]);
      }
    }
  }

  /// [configJson] is `en_core_web_sm.json`; [weights] the `.bin` contents.
  factory SpacyEnglish.load(String configJson, Uint8List weights) =>
      SpacyEnglish._(
        jsonDecode(configJson) as Map<String, dynamic>,
        ByteData.sublistView(weights),
      );

  final Map<String, dynamic> _config;
  final RegExp _prefix, _suffix, _infix, _url;
  final Map<String, List<(String, String?)>> _rules;
  final Map<String, String> _lexemeNorm;
  final Map<String, String> _baseNorms;
  final Map<String, int> _symbols;
  final List<String> labels;

  /// Special cases containing affixes, keyed by first token, as token texts.
  final Map<String, List<List<String>>> _matcher = {};

  // ---------------------------------------------------------------------
  // Tokenizer (spacy/tokenizer.pyx).

  List<SpacyToken> tokenize(String text) {
    final doc = _tokenizeAffixes(text, withSpecialCases: true);
    _applySpecialCases(doc, text);
    return doc;
  }

  List<SpacyToken> _tokenizeAffixes(
    String string, {
    required bool withSpecialCases,
  }) {
    final doc = <SpacyToken>[];
    if (string.isEmpty) return doc;
    // Iterate by code point, but track UTF-16 offsets for substring().
    final runes = string.runes.toList();
    var start = 0; // UTF-16 offset
    var pos = 0;
    var inWs = _isSpaceChar(String.fromCharCode(runes.first));
    void emit(int a, int b) {
      final span = string.substring(a, b);
      final before = doc.length;
      _tokenizeSpan(doc, span, withSpecialCases);
      var idx = a;
      for (var i = before; i < doc.length; i++) {
        doc[i].idx = idx;
        idx += doc[i].text.length;
      }
    }

    for (final r in runes) {
      final uc = String.fromCharCode(r);
      if (_isSpaceChar(uc) != inWs) {
        if (start < pos) emit(start, pos);
        if (uc == ' ') {
          if (doc.isNotEmpty) doc.last.spacy = true;
          start = pos + 1;
        } else {
          start = pos;
        }
        inWs = !inWs;
      }
      pos += uc.length;
    }
    if (start < pos) {
      emit(start, string.length);
      doc.last.spacy = string.endsWith(' ') && !inWs;
    }
    return doc;
  }

  bool _isSpecial(String s, bool withSpecialCases) =>
      withSpecialCases && _rules.containsKey(s);

  void _pushSpecial(List<SpacyToken> doc, String s) {
    for (final (orth, norm) in _rules[s]!) {
      doc.add(SpacyToken(orth, norm: norm));
    }
  }

  void _tokenizeSpan(List<SpacyToken> doc, String span, bool specials) {
    if (_isSpecial(span, specials)) {
      _pushSpecial(doc, span);
      return;
    }
    final prefixes = <String>[];
    final suffixes = <String>[];
    var string = span;
    var lastSize = -1;
    while (string.isNotEmpty && string.length != lastSize) {
      if (_isSpecial(string, specials)) break;
      lastSize = string.length;
      final preLen = _findPrefix(string);
      if (preLen != 0) {
        final minusPre = string.substring(preLen);
        if (minusPre.isNotEmpty && _isSpecial(minusPre, specials)) {
          prefixes.add(string.substring(0, preLen));
          string = minusPre;
          break;
        }
      }
      final sufLen = _findSuffix(string.substring(preLen));
      if (sufLen != 0) {
        final minusSuf = string.substring(0, string.length - sufLen);
        if (minusSuf.isNotEmpty && _isSpecial(minusSuf, specials)) {
          suffixes.add(string.substring(string.length - sufLen));
          string = minusSuf;
          break;
        }
      }
      if (preLen != 0 && sufLen != 0 && preLen + sufLen <= string.length) {
        prefixes.add(string.substring(0, preLen));
        suffixes.add(string.substring(string.length - sufLen));
        string = string.substring(preLen, string.length - sufLen);
      } else if (preLen != 0) {
        prefixes.add(string.substring(0, preLen));
        string = string.substring(preLen);
      } else if (sufLen != 0) {
        suffixes.add(string.substring(string.length - sufLen));
        string = string.substring(0, string.length - sufLen);
      }
    }
    for (final p in prefixes) {
      doc.add(SpacyToken(p));
    }
    if (string.isNotEmpty) {
      if (_isSpecial(string, specials)) {
        _pushSpecial(doc, string);
      } else if (_url.hasMatch(string)) {
        doc.add(SpacyToken(string));
      } else {
        final matches = _infix.allMatches(string).toList();
        if (matches.isEmpty) {
          doc.add(SpacyToken(string));
        } else {
          var start = 0;
          for (final m in matches) {
            if (m.start == 0) continue;
            if (m.start != start) {
              doc.add(SpacyToken(string.substring(start, m.start)));
            }
            if (m.start != m.end) doc.add(SpacyToken(m[0]!));
            start = m.end;
          }
          if (start < string.length) {
            doc.add(SpacyToken(string.substring(start)));
          }
        }
      }
    }
    for (final s in suffixes.reversed) {
      doc.add(SpacyToken(s));
    }
  }

  int _findPrefix(String s) {
    final m = _prefix.firstMatch(s);
    return m == null ? 0 : m.end - m.start;
  }

  int _findSuffix(String s) {
    final m = _suffix.firstMatch(s);
    return m == null ? 0 : m.end - m.start;
  }

  void _applySpecialCases(List<SpacyToken> doc, String text) {
    final matches = <(int, int)>[];
    for (var i = 0; i < doc.length; i++) {
      final candidates = _matcher[doc[i].text];
      if (candidates == null) continue;
      for (final seq in candidates) {
        if (i + seq.length > doc.length) continue;
        var ok = true;
        for (var j = 1; j < seq.length && ok; j++) {
          ok = doc[i + j].text == seq[j];
        }
        if (ok) matches.add((i, i + seq.length));
      }
    }
    if (matches.isEmpty) return;
    // Longest first, then latest start; skip spans overlapping chosen ones.
    matches.sort((a, b) {
      final la = a.$2 - a.$1, lb = b.$2 - b.$1;
      return la != lb ? la.compareTo(lb) : a.$1.compareTo(b.$1);
    });
    final seen = <int>{};
    final filtered = <(int, int)>[];
    for (final m in matches.reversed) {
      if (!seen.contains(m.$1) && !seen.contains(m.$2 - 1)) filtered.add(m);
      for (var k = m.$1; k < m.$2; k++) {
        seen.add(k);
      }
    }
    filtered.sort((a, b) => a.$1.compareTo(b.$1));
    for (final (start, end) in filtered.reversed) {
      final first = doc[start], last = doc[end - 1];
      final spanText = text.substring(first.idx, last.idx + last.text.length);
      final rule = _rules[spanText];
      if (rule == null) continue;
      final finalSpacy = last.spacy;
      var idx = first.idx;
      final replacement = <SpacyToken>[];
      for (final (orth, norm) in rule) {
        replacement.add(SpacyToken(orth, norm: norm, idx: idx));
        idx += orth.length;
      }
      replacement.last.spacy = finalSpacy;
      doc.replaceRange(start, end, replacement);
    }
  }

  // ---------------------------------------------------------------------
  // Lexical attributes and hashing.

  /// spaCy `StringStore` id: 0 for "", symbol ids for symbols, else hash.
  U64 stringId(String s) {
    if (s.isEmpty) return U64.zero;
    final symbol = _symbols[s];
    return symbol == null ? spacyHashString(s) : U64.from(symbol);
  }

  String norm(SpacyToken t) {
    if (t.norm != null) return t.norm!;
    final fromTable = _lexemeNorm[stringId(t.text).hex];
    if (fromTable != null) return fromTable;
    return _baseNorms[t.text] ?? t.text.toLowerCase();
  }

  static final _alphaRe = RegExp(r'^\p{L}$', unicode: true);
  static final _upperRe = RegExp(r'^\p{Lu}$', unicode: true);
  static final _digitRe = RegExp(r'^\p{Nd}$', unicode: true);

  static String wordShape(String text) {
    final runes = text.runes.toList();
    if (runes.length >= 100) return 'LONG';
    final shape = StringBuffer();
    var last = '';
    var seq = 0;
    for (final r in runes) {
      final c = String.fromCharCode(r);
      String s;
      if (_alphaRe.hasMatch(c)) {
        s = _upperRe.hasMatch(c) ? 'X' : 'x';
      } else if (_digitRe.hasMatch(c)) {
        s = 'd';
      } else {
        s = c;
      }
      if (s == last) {
        seq++;
      } else {
        seq = 0;
        last = s;
      }
      if (seq < 4) shape.write(s);
    }
    return shape.toString();
  }

  /// Feature ids per token: NORM, PREFIX, SUFFIX, SHAPE, SPACY, IS_SPACE.
  List<List<U64>> features(List<SpacyToken> doc) => [
    for (final t in doc)
      () {
        final runes = t.text.runes.toList();
        final prefix = runes.isEmpty ? '' : String.fromCharCode(runes.first);
        final suffix = String.fromCharCodes(
          runes.sublist(math.max(0, runes.length - 3)),
        );
        return [
          stringId(norm(t)),
          stringId(prefix),
          stringId(suffix),
          stringId(wordShape(t.text)),
          U64.from(t.spacy ? 1 : 0),
          U64.from(_allSpaceRe.hasMatch(t.text) ? 1 : 0),
        ];
      }(),
  ];

  // ---------------------------------------------------------------------
  // Network (thinc tok2vec: MultiHashEmbed + MaxoutWindowEncoder; softmax).

  late final List<(Float32List, int, int)> _embed; // (E, rows, seed)
  late final List<(Float32List, Float32List, int, int, int)> _maxout;
  late final List<(Float32List, Float32List)> _layernorm;
  late final Float32List _softmaxW, _softmaxB;
  static const _width = 96;

  void _loadLayers(ByteData data) {
    Float32List tensor(Map t) {
      final shape = (t['shape'] as List).cast<int>();
      final n = shape.fold(1, (a, b) => a * b);
      final out = Float32List(n);
      final off = t['offset'] as int;
      for (var i = 0; i < n; i++) {
        out[i] = data.getFloat32(off + i * 4, Endian.little);
      }
      return out;
    }

    final embed = <(Float32List, int, int)>[];
    final maxout = <(Float32List, Float32List, int, int, int)>[];
    final ln = <(Float32List, Float32List)>[];
    for (final l in (_config['layers'] as List).cast<Map>()) {
      final ts = (l['tensors'] as List).cast<Map>();
      switch (l['type']) {
        case 'hashembed':
          embed.add((
            tensor(ts[0]),
            (ts[0]['shape'] as List)[0] as int,
            l['seed'] as int,
          ));
        case 'maxout':
          final s = (ts[0]['shape'] as List).cast<int>();
          maxout.add((tensor(ts[0]), tensor(ts[1]), s[0], s[1], s[2]));
        case 'layernorm':
          ln.add((tensor(ts[0]), tensor(ts[1])));
        case 'softmax':
          _softmaxW = tensor(ts[0]);
          _softmaxB = tensor(ts[1]);
      }
    }
    _embed = embed;
    _maxout = maxout;
    _layernorm = ln;
  }

  static Float32List _maxoutLayer(
    Float32List x,
    int rows,
    (Float32List, Float32List, int, int, int) layer,
  ) {
    final (w, b, nO, nP, nI) = layer;
    final out = Float32List(rows * nO);
    for (var r = 0; r < rows; r++) {
      final xo = r * nI;
      for (var o = 0; o < nO; o++) {
        var best = double.negativeInfinity;
        for (var p = 0; p < nP; p++) {
          final wo = (o * nP + p) * nI;
          var acc = b[o * nP + p].toDouble();
          for (var i = 0; i < nI; i++) {
            acc += w[wo + i] * x[xo + i];
          }
          if (acc > best) best = acc;
        }
        out[r * nO + o] = best;
      }
    }
    return out;
  }

  static void _layerNorm(
    Float32List x,
    int rows,
    (Float32List, Float32List) p,
  ) {
    final (g, b) = p;
    for (var r = 0; r < rows; r++) {
      final o = r * _width;
      var mu = 0.0;
      for (var i = 0; i < _width; i++) {
        mu += x[o + i];
      }
      mu /= _width;
      var v = 0.0;
      for (var i = 0; i < _width; i++) {
        final d = x[o + i] - mu;
        v += d * d;
      }
      final inv = 1 / math.sqrt(v / _width + 1e-8);
      for (var i = 0; i < _width; i++) {
        x[o + i] = (x[o + i] - mu) * inv * g[i] + b[i];
      }
    }
  }

  static Float32List _window(Float32List x, int rows) {
    final out = Float32List(rows * _width * 3);
    for (var r = 0; r < rows; r++) {
      final o = r * _width * 3;
      if (r > 0) out.setRange(o, o + _width, x, (r - 1) * _width);
      out.setRange(o + _width, o + 2 * _width, x, r * _width);
      if (r + 1 < rows) {
        out.setRange(o + 2 * _width, o + 3 * _width, x, (r + 1) * _width);
      }
    }
    return out;
  }

  /// Sets [SpacyToken.tag] on every token.
  void tag(List<SpacyToken> doc) {
    final n = doc.length;
    if (n == 0) return;
    final feats = features(doc);
    final nIn = _width * _embed.length;
    final x0 = Float32List(n * nIn);
    for (var c = 0; c < _embed.length; c++) {
      final (e, rows, seed) = _embed[c];
      for (var t = 0; t < n; t++) {
        final o = t * nIn + c * _width;
        for (final k in thincHash128(feats[t][c], seed)) {
          final row = (k % rows) * _width;
          for (var i = 0; i < _width; i++) {
            x0[o + i] += e[row + i];
          }
        }
      }
    }
    final x1 = _maxoutLayer(x0, n, _maxout[0]);
    _layerNorm(x1, n, _layernorm[0]);
    // thinc's with_array(pad=4): zero rows around the sequence, which the
    // residual blocks then transform, so boundary tokens see them.
    const pad = 4;
    final rows = n + 2 * pad;
    var x = Float32List(rows * _width)
      ..setRange(pad * _width, (pad + n) * _width, x1);
    for (var blk = 1; blk < _maxout.length; blk++) {
      final y = _maxoutLayer(_window(x, rows), rows, _maxout[blk]);
      _layerNorm(y, rows, _layernorm[blk]);
      for (var i = 0; i < y.length; i++) {
        y[i] += x[i];
      }
      x = y;
    }
    final nLabels = labels.length;
    for (var t = 0; t < n; t++) {
      final o = (t + pad) * _width;
      var best = 0;
      var bestScore = double.negativeInfinity;
      for (var l = 0; l < nLabels; l++) {
        var s = _softmaxB[l].toDouble();
        for (var i = 0; i < _width; i++) {
          s += _softmaxW[l * _width + i] * x[o + i];
        }
        if (s > bestScore) {
          bestScore = s;
          best = l;
        }
      }
      doc[t].tag = labels[best];
    }
  }

  /// Tokenizes and tags [text].
  List<SpacyToken> call(String text) {
    final doc = tokenize(text);
    tag(doc);
    return doc;
  }
}
