/// Dart port of misaki's English G2P (hexgrad/misaki 0.9.4, `misaki/en.py`,
/// Apache-2.0). Produces the phoneme strings Kokoro was trained on.
///
/// The port is deliberately literal so it can be checked against Python
/// goldens; comments note where Python semantics needed care. The tokenizer
/// and part-of-speech tagger (spaCy upstream) live in `misaki_tokenizer.dart`.
library;

import 'package:fonnx/models/kokoro/misaki/num2words_en.dart';

/// One token, mirroring misaki's `MToken` plus its `_` extension fields.
class MToken {
  MToken({
    required this.text,
    required this.tag,
    required this.whitespace,
    this.phonemes,
    this.isHead = true,
    this.alias,
    this.stress,
    this.currency,
    this.numFlags = '',
    this.prespace = false,
    this.rating,
  });

  String text;
  String tag;
  String whitespace;
  String? phonemes;
  bool isHead;
  String? alias;
  double? stress;
  String? currency;
  String numFlags;
  bool prespace;
  int? rating;

  MToken copyWith({String? text, String? whitespace}) => MToken(
    text: text ?? this.text,
    tag: tag,
    whitespace: whitespace ?? this.whitespace,
    phonemes: phonemes,
    isHead: isHead,
    alias: alias,
    stress: stress,
    currency: currency,
    numFlags: numFlags,
    prespace: prespace,
    rating: rating,
  );

  @override
  String toString() => 'MToken($text, $tag, "$whitespace", $phonemes)';
}

// ---------------------------------------------------------------------------
// Python string helpers.

final _alphaRe = RegExp(r'^\p{L}+$', unicode: true);
final _spaceRe = RegExp(r'^\s$', unicode: true);
final _digitsRe = RegExp(r'^[0-9]+$');

bool _isAlpha(String s) => _alphaRe.hasMatch(s);
bool _isSpace(String c) => _spaceRe.hasMatch(c);
bool _isDigit(String s) => _digitsRe.hasMatch(s);
bool _isLower(String s) => s == s.toLowerCase();
bool _isUpper(String s) => s == s.toUpperCase();
List<String> _chars(String s) =>
    s.runes.map(String.fromCharCode).toList(growable: false);

String _capitalize(String s) {
  if (s.isEmpty) return s;
  final c = _chars(s);
  return c.first.toUpperCase() + c.skip(1).join().toLowerCase();
}

String _strip(String s, String chars) {
  var a = 0, b = s.length;
  while (a < b && chars.contains(s[a])) {
    a++;
  }
  while (b > a && chars.contains(s[b - 1])) {
    b--;
  }
  return s.substring(a, b);
}

String _rstrip(String s, String chars) {
  var b = s.length;
  while (b > 0 && chars.contains(s[b - 1])) {
    b--;
  }
  return s.substring(0, b);
}

/// Python's `str.lstrip()` with no arguments.
String _lstripSpace(String s) {
  var a = 0;
  while (a < s.length && _isSpace(s[a])) {
    a++;
  }
  return s.substring(a);
}

/// The subset of NFKC that matters for English text. Dart has no built-in
/// Unicode normalization; misaki applies NFKC per word before lookup.
String _nfkcLite(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    if (r >= 0xFF01 && r <= 0xFF5E) {
      b.writeCharCode(r - 0xFEE0); // fullwidth ASCII
    } else {
      final m = _nfkcMap[r];
      if (m != null) {
        b.write(m);
      } else {
        b.writeCharCode(r);
      }
    }
  }
  return b.toString();
}

const Map<int, String> _nfkcMap = {
  0x00A0: ' ',
  0x2026: '...',
  0xFB00: 'ff',
  0xFB01: 'fi',
  0xFB02: 'fl',
  0xFB03: 'ffi',
  0xFB04: 'ffl',
  0xFB05: 'st',
  0xFB06: 'st',
  0x017F: 's',
  0x00B5: 'μ',
  0x2070: '0',
  0x00B9: '1',
  0x00B2: '2',
  0x00B3: '3',
  0x2074: '4',
  0x2075: '5',
  0x2076: '6',
  0x2077: '7',
  0x2078: '8',
  0x2079: '9',
  0x2080: '0',
  0x2081: '1',
  0x2082: '2',
  0x2083: '3',
  0x2084: '4',
  0x2085: '5',
  0x2086: '6',
  0x2087: '7',
  0x2088: '8',
  0x2089: '9',
  0x2122: 'TM',
  0x2002: ' ',
  0x2003: ' ',
  0x2009: ' ',
  0x3000: ' ',
};

// ---------------------------------------------------------------------------
// Constants.

const _diphthongs = 'AIOQWYʤʧ';
const _subtokenJunks = "',-._‘’/";
const _puncts = ';:,.!?—…"“”';
const _nonQuotePuncts = ';:,.!?—…';
const _punctTags = {
  '.',
  ',',
  '-LRB-',
  '-RRB-',
  '``',
  '""',
  "''",
  ':',
  r'$',
  '#',
  'NFP',
};
const _punctTagPhonemes = {
  '-LRB-': '(',
  '-RRB-': ')',
  '``': '\u201C',
  '""': '\u201D',
  "''": '\u201D',
};
const _consonants = 'bdfhjklmnpstvwzðŋɡɹɾʃʒʤʧθ';
const _usTaus = 'AIOWYiuæɑəɛɪɹʊʌ';
const _currencies = {
  r'$': ('dollar', 'cent'),
  '£': ('pound', 'pence'),
  '€': ('euro', 'cent'),
};
const _ordinals = {'st', 'nd', 'rd', 'th'};
const _addSymbols = {'.': 'dot', '/': 'slash'};
const _symbols = {'%': 'percent', '&': 'and', '+': 'plus', '@': 'at'};
const _primaryStress = 'ˈ';
const _secondaryStress = 'ˌ';
const _stresses = 'ˌˈ';
const _vowels = 'AIOQWYaiuæɑɒɔəɛɜɪʊʌᵻ';

bool _isLexiconOrd(int r) =>
    r == 39 || r == 45 || (r >= 65 && r <= 90) || (r >= 97 && r <= 122);
bool _allLexiconOrds(String s) => s.runes.every(_isLexiconOrd);

final _subtokenRe = RegExp(
  r"^['‘’]+|\p{Lu}(?=\p{Lu}\p{Ll})|(?:^-)?(?:\p{Nd}?[,.]?\p{Nd})+|[-_]+|"
  r"['‘’]{2,}|\p{L}*?(?:['‘’]\p{L})*?\p{Ll}(?=\p{Lu})|\p{L}+(?:['‘’]\p{L})*|"
  r"[^-_\p{L}'‘’\p{Nd}]|['‘’]+$",
  unicode: true,
);

List<String> subtokenize(String word) =>
    _subtokenRe.allMatches(word).map((m) => m[0]!).toList();

final _linkRe = RegExp(r'\[([^\]]+)\]\(([^\)]*)\)');

// ---------------------------------------------------------------------------
// Stress.

int stressWeight(String? ps) {
  if (ps == null || ps.isEmpty) return 0;
  var w = 0;
  for (final c in _chars(ps)) {
    w += _diphthongs.contains(c) ? 2 : 1;
  }
  return w;
}

String _restress(String ps) {
  final chars = _chars(ps);
  final ips = <(double, String)>[
    for (var i = 0; i < chars.length; i++) (i.toDouble(), chars[i]),
  ];
  for (var i = 0; i < chars.length; i++) {
    if (!_stresses.contains(chars[i])) continue;
    var j = i;
    while (!_vowels.contains(chars[j])) {
      j++; // Python raises StopIteration if no vowel; callers guarantee one.
    }
    ips[i] = (j - 0.5, chars[i]);
  }
  ips.sort((a, b) {
    final c = a.$1.compareTo(b.$1);
    return c != 0 ? c : a.$2.compareTo(b.$2);
  });
  return ips.map((e) => e.$2).join();
}

bool _hasAny(String s, String chars) {
  for (final c in _chars(chars)) {
    if (s.contains(c)) return true;
  }
  return false;
}

String? applyStress(String? ps, double? stress) {
  if (stress == null || ps == null) return ps;
  if (stress < -1) {
    return ps.replaceAll(_primaryStress, '').replaceAll(_secondaryStress, '');
  } else if (stress == -1 ||
      ((stress == 0 || stress == -0.5) && ps.contains(_primaryStress))) {
    return ps
        .replaceAll(_secondaryStress, '')
        .replaceAll(_primaryStress, _secondaryStress);
  } else if ((stress == 0 || stress == 0.5 || stress == 1) &&
      !_hasAny(ps, _stresses)) {
    if (!_hasAny(ps, _vowels)) return ps;
    return _restress(_secondaryStress + ps);
  } else if (stress >= 1 &&
      !ps.contains(_primaryStress) &&
      ps.contains(_secondaryStress)) {
    return ps.replaceAll(_secondaryStress, _primaryStress);
  } else if (stress > 1 && !_hasAny(ps, _stresses)) {
    if (!_hasAny(ps, _vowels)) return ps;
    return _restress(_primaryStress + ps);
  }
  return ps;
}

// ---------------------------------------------------------------------------
// Token helpers.

MToken mergeTokens(List<MToken> tokens, {String? unk}) {
  final stress = <double>{
    for (final tk in tokens)
      if (tk.stress != null) tk.stress!,
  };
  final currency = <String>{
    for (final tk in tokens)
      if (tk.currency != null) tk.currency!,
  };
  final ratings = [for (final tk in tokens) tk.rating];
  String? phonemes;
  if (unk != null) {
    final b = StringBuffer();
    for (final tk in tokens) {
      final s = b.toString();
      if (tk.prespace &&
          s.isNotEmpty &&
          !_isSpace(s[s.length - 1]) &&
          tk.phonemes != null &&
          tk.phonemes!.isNotEmpty) {
        b.write(' ');
      }
      b.write(tk.phonemes ?? unk);
    }
    phonemes = b.toString();
  }
  int weight(MToken tk) {
    var w = 0;
    for (final c in _chars(tk.text)) {
      w += c == c.toLowerCase() ? 1 : 2;
    }
    return w;
  }

  var tagToken = tokens.first;
  for (final tk in tokens.skip(1)) {
    if (weight(tk) > weight(tagToken)) tagToken = tk;
  }
  final text = StringBuffer();
  for (var i = 0; i < tokens.length - 1; i++) {
    text
      ..write(tokens[i].text)
      ..write(tokens[i].whitespace);
  }
  text.write(tokens.last.text);
  final flags = <String>{
    for (final tk in tokens) ..._chars(tk.numFlags),
  }.toList()..sort();
  String? maxCurrency;
  for (final c in currency) {
    if (maxCurrency == null || c.compareTo(maxCurrency) > 0) maxCurrency = c;
  }
  return MToken(
    text: text.toString(),
    tag: tagToken.tag,
    whitespace: tokens.last.whitespace,
    phonemes: phonemes,
    isHead: tokens.first.isHead,
    stress: stress.length == 1 ? stress.first : null,
    currency: maxCurrency,
    numFlags: flags.join(),
    prespace: tokens.first.prespace,
    rating: ratings.contains(null)
        ? null
        : ratings.cast<int>().reduce((a, b) => a < b ? a : b),
  );
}

class TokenContext {
  const TokenContext({this.futureVowel, this.futureTo = false});
  final bool? futureVowel;
  final bool futureTo;
}

/// A phoneme string and its rating (5 user, 4 gold, 3 silver).
typedef MisakiPs = (String?, int?);

/// Out-of-vocabulary handler: given a token, returns phonemes and a rating.
typedef MisakiFallback = MisakiPs Function(MToken token);
const MisakiPs _none = (null, null);

// ---------------------------------------------------------------------------
// Lexicon.

/// Gold/silver dictionaries plus misaki's rule-based lookup.
///
/// Values are either a phoneme string or a map from POS tag to phonemes
/// (with a `DEFAULT` key). Load from misaki's `us_gold.json` and
/// `us_silver.json`.
class MisakiLexicon {
  MisakiLexicon({
    required Map<String, dynamic> gold,
    required Map<String, dynamic> silver,
    this.british = false,
  }) : golds = _growDictionary(gold),
       silvers = _growDictionary(silver);

  final bool british;
  final Map<String, Object?> golds;
  final Map<String, Object?> silvers;
  static const _capStresses = (0.5, 2.0);

  static Map<String, Object?> _growDictionary(Map<String, dynamic> d) {
    final e = <String, Object?>{};
    for (final MapEntry(:key, :value) in d.entries) {
      if (key.length < 2) continue;
      if (key == key.toLowerCase()) {
        final cap = _capitalize(key);
        if (key != cap) e[cap] = value;
      } else if (key == _capitalize(key.toLowerCase())) {
        e[key.toLowerCase()] = value;
      }
    }
    return {...e, ...d};
  }

  String _goldString(String key) => golds[key]! as String;

  MisakiPs getNNP(String word) {
    final b = StringBuffer();
    for (final c in _chars(word)) {
      if (!_isAlpha(c)) continue;
      final p = golds[c.toUpperCase()];
      if (p is! String) return _none;
      b.write(p);
    }
    final ps = applyStress(b.toString(), 0)!;
    final i = ps.lastIndexOf(_secondaryStress);
    if (i < 0) return (ps, 3);
    return (ps.substring(0, i) + _primaryStress + ps.substring(i + 1), 3);
  }

  static final _vsRe = RegExp(r'^vs\.?$', caseSensitive: false);

  MisakiPs getSpecialCase(
    String word,
    String? tag,
    double? stress,
    TokenContext ctx,
  ) {
    if (tag == 'ADD' && _addSymbols.containsKey(word)) {
      return lookup(_addSymbols[word]!, null, -0.5, ctx);
    } else if (_symbols.containsKey(word)) {
      return lookup(_symbols[word]!, null, null, ctx);
    } else if (_strip(word, '.').contains('.') &&
        _isAlpha(word.replaceAll('.', '')) &&
        word.split('.').map((s) => s.length).reduce((a, b) => a > b ? a : b) <
            3) {
      return getNNP(word);
    } else if (word == 'a' || word == 'A') {
      return (tag == 'DT' ? 'ɐ' : 'ˈA', 4);
    } else if (word == 'am' || word == 'Am' || word == 'AM') {
      if (tag != null && tag.startsWith('NN')) {
        return getNNP(word);
      } else if (ctx.futureVowel == null ||
          word != 'am' ||
          (stress != null && stress != 0 && stress > 0)) {
        return (_goldString('am'), 4);
      }
      return ('ɐm', 4);
    } else if (word == 'an' || word == 'An' || word == 'AN') {
      if (word == 'AN' && tag != null && tag.startsWith('NN')) {
        return getNNP(word);
      }
      return ('ɐn', 4);
    } else if (word == 'I' && tag == 'PRP') {
      return ('${_secondaryStress}I', 4);
    } else if ((word == 'by' || word == 'By' || word == 'BY') &&
        getParentTag(tag) == 'ADV') {
      return ('bˈI', 4);
    } else if (word == 'to' ||
        word == 'To' ||
        (word == 'TO' && (tag == 'TO' || tag == 'IN'))) {
      return switch (ctx.futureVowel) {
        null => (_goldString('to'), 4),
        false => ('tə', 4),
        true => ('tʊ', 4),
      };
    } else if (word == 'in' || word == 'In' || (word == 'IN' && tag != 'NNP')) {
      final s = ctx.futureVowel == null || tag != 'IN' ? _primaryStress : '';
      return ('$sɪn', 4);
    } else if (word == 'the' ||
        word == 'The' ||
        (word == 'THE' && tag == 'DT')) {
      return (ctx.futureVowel == true ? 'ði' : 'ðə', 4);
    } else if (tag == 'IN' && _vsRe.hasMatch(word)) {
      return lookup('versus', null, null, ctx);
    } else if (word == 'used' || word == 'Used' || word == 'USED') {
      final used = golds['used']! as Map;
      if ((tag == 'VBD' || tag == 'JJ') && ctx.futureTo) {
        return (used['VBD'] as String, 4);
      }
      return (used['DEFAULT'] as String, 4);
    }
    return _none;
  }

  static String? getParentTag(String? tag) {
    if (tag == null) return tag;
    if (tag.startsWith('VB')) return 'VERB';
    if (tag.startsWith('NN')) return 'NOUN';
    if (tag.startsWith('ADV') || tag.startsWith('RB')) return 'ADV';
    if (tag.startsWith('ADJ') || tag.startsWith('JJ')) return 'ADJ';
    return tag;
  }

  bool isKnown(String word, String? tag) {
    if (golds.containsKey(word) ||
        _symbols.containsKey(word) ||
        silvers.containsKey(word)) {
      return true;
    } else if (!_isAlpha(word) || !_allLexiconOrds(word)) {
      return false;
    } else if (word.length == 1) {
      return true;
    } else if (word == word.toUpperCase() &&
        golds.containsKey(word.toLowerCase())) {
      return true;
    }
    final rest = word.substring(1);
    return rest == rest.toUpperCase();
  }

  MisakiPs lookup(String word, String? tag, double? stress, TokenContext? ctx) {
    bool? isNNP;
    if (word == word.toUpperCase() && !golds.containsKey(word)) {
      word = word.toLowerCase();
      isNNP = tag == 'NNP';
    }
    Object? ps = golds[word];
    int? rating = 4;
    if (ps == null && isNNP != true) {
      ps = silvers[word];
      rating = 3;
    }
    if (ps is Map) {
      if (ctx != null && ctx.futureVowel == null && ps.containsKey('None')) {
        tag = 'None';
      } else if (!ps.containsKey(tag)) {
        tag = getParentTag(tag);
      }
      ps = ps.containsKey(tag) ? ps[tag] : ps['DEFAULT'];
    }
    final s = ps as String?;
    if (s == null || (isNNP == true && !s.contains(_primaryStress))) {
      final nnp = getNNP(word);
      if (nnp.$1 != null) return nnp;
    }
    return (applyStress(s, stress), rating);
  }

  String? _s(String? stem) {
    if (stem == null || stem.isEmpty) return null;
    final last = stem[stem.length - 1];
    if ('ptkfθ'.contains(last)) return '${stem}s';
    if ('szʃʒʧʤ'.contains(last)) return '$stem${british ? 'ɪ' : 'ᵻ'}z';
    return '${stem}z';
  }

  MisakiPs stemS(String word, String? tag, double? stress, TokenContext? ctx) {
    if (word.length < 3 || !word.endsWith('s')) return _none;
    String stem;
    if (!word.endsWith('ss') &&
        isKnown(word.substring(0, word.length - 1), tag)) {
      stem = word.substring(0, word.length - 1);
    } else if ((word.endsWith("'s") ||
            (word.length > 4 &&
                word.endsWith('es') &&
                !word.endsWith('ies'))) &&
        isKnown(word.substring(0, word.length - 2), tag)) {
      stem = word.substring(0, word.length - 2);
    } else if (word.length > 4 &&
        word.endsWith('ies') &&
        isKnown('${word.substring(0, word.length - 3)}y', tag)) {
      stem = '${word.substring(0, word.length - 3)}y';
    } else {
      return _none;
    }
    final (ps, rating) = lookup(stem, tag, stress, ctx);
    return (_s(ps), rating);
  }

  String? _ed(String? stem) {
    if (stem == null || stem.isEmpty) return null;
    final last = stem[stem.length - 1];
    if ('pkfθʃsʧ'.contains(last)) return '${stem}t';
    if (last == 'd') return '$stem${british ? 'ɪ' : 'ᵻ'}d';
    if (last != 't') return '${stem}d';
    if (british || stem.length < 2) return '$stemɪd';
    if (_usTaus.contains(stem[stem.length - 2])) {
      return '${stem.substring(0, stem.length - 1)}ɾᵻd';
    }
    return '$stemᵻd';
  }

  MisakiPs stemEd(String word, String? tag, double? stress, TokenContext? ctx) {
    if (word.length < 4 || !word.endsWith('d')) return _none;
    String stem;
    if (!word.endsWith('dd') &&
        isKnown(word.substring(0, word.length - 1), tag)) {
      stem = word.substring(0, word.length - 1);
    } else if (word.length > 4 &&
        word.endsWith('ed') &&
        !word.endsWith('eed') &&
        isKnown(word.substring(0, word.length - 2), tag)) {
      stem = word.substring(0, word.length - 2);
    } else {
      return _none;
    }
    final (ps, rating) = lookup(stem, tag, stress, ctx);
    return (_ed(ps), rating);
  }

  String? _ing(String? stem) {
    if (stem == null || stem.isEmpty) return null;
    final last = stem[stem.length - 1];
    if (british) {
      if ('əː'.contains(last)) return null;
    } else if (stem.length > 1 &&
        last == 't' &&
        _usTaus.contains(stem[stem.length - 2])) {
      return '${stem.substring(0, stem.length - 1)}ɾɪŋ';
    }
    return '$stemɪŋ';
  }

  static final _doubledIngRe = RegExp(r'([bcdgklmnprstvxz])\1ing$|cking$');

  MisakiPs stemIng(
    String word,
    String? tag,
    double? stress,
    TokenContext? ctx,
  ) {
    if (word.length < 5 || !word.endsWith('ing')) return _none;
    final base = word.substring(0, word.length - 3);
    String stem;
    if (word.length > 5 && isKnown(base, tag)) {
      stem = base;
    } else if (isKnown('${base}e', tag)) {
      stem = '${base}e';
    } else if (word.length > 5 &&
        _doubledIngRe.hasMatch(word) &&
        isKnown(word.substring(0, word.length - 4), tag)) {
      stem = word.substring(0, word.length - 4);
    } else {
      return _none;
    }
    final (ps, rating) = lookup(stem, tag, stress, ctx);
    return (_ing(ps), rating);
  }

  MisakiPs getWord(String word, String? tag, double? stress, TokenContext ctx) {
    final special = getSpecialCase(word, tag, stress, ctx);
    if (special.$1 != null) return special;
    final wl = word.toLowerCase();
    if (word.length > 1 &&
        _isAlpha(word.replaceAll("'", '')) &&
        word != wl &&
        (tag != 'NNP' || word.length > 7) &&
        !golds.containsKey(word) &&
        !silvers.containsKey(word) &&
        (word == word.toUpperCase() ||
            word.substring(1) == word.substring(1).toLowerCase()) &&
        (golds.containsKey(wl) ||
            silvers.containsKey(wl) ||
            _truthy(stemS(wl, tag, stress, ctx).$1) ||
            _truthy(stemEd(wl, tag, stress, ctx).$1) ||
            _truthy(stemIng(wl, tag, stress, ctx).$1))) {
      word = wl;
    }
    if (isKnown(word, tag)) {
      return lookup(word, tag, stress, ctx);
    } else if (word.endsWith("s'") &&
        isKnown("${word.substring(0, word.length - 2)}'s", tag)) {
      return lookup(
        "${word.substring(0, word.length - 2)}'s",
        tag,
        stress,
        ctx,
      );
    } else if (word.endsWith("'") &&
        isKnown(word.substring(0, word.length - 1), tag)) {
      return lookup(word.substring(0, word.length - 1), tag, stress, ctx);
    }
    final s = stemS(word, tag, stress, ctx);
    if (s.$1 != null) return s;
    final ed = stemEd(word, tag, stress, ctx);
    if (ed.$1 != null) return ed;
    final ing = stemIng(word, tag, stress ?? 0.5, ctx);
    if (ing.$1 != null) return ing;
    return _none;
  }

  static bool _truthy(String? s) => s != null && s.isNotEmpty;

  static bool isCurrency(String word) {
    if (!word.contains('.')) return true;
    if ('.'.allMatches(word).length > 1) return false;
    // Python also tests `set(cents) == {0}`, which compares str to int and
    // is always false.
    return word.split('.')[1].length < 3;
  }

  static final _numSuffixRe = RegExp(r"[a-z']+$");
  static final _nonLettersRe = RegExp(r'[^a-z]+');

  MisakiPs getNumber(
    String word,
    String? currency,
    bool isHead,
    String numFlags,
  ) {
    final suffix = _numSuffixRe.firstMatch(word)?[0];
    if (suffix != null) word = word.substring(0, word.length - suffix.length);
    final result = <MisakiPs>[];
    if (word.startsWith('-')) {
      result.add(lookup('minus', null, null, null));
      word = word.substring(1);
    }
    void extendNum(String num, {bool first = true, bool escape = false}) {
      final source = escape ? num : num2wordsCardinal(BigInt.parse(num));
      final splits = source.split(_nonLettersRe);
      for (var i = 0; i < splits.length; i++) {
        final w = splits[i];
        if (w != 'and' || numFlags.contains('&')) {
          if (first &&
              i == 0 &&
              splits.length > 1 &&
              w == 'one' &&
              numFlags.contains('a')) {
            result.add(('ə', 4));
          } else {
            result.add(lookup(w, null, w == 'point' ? -2 : null, null));
          }
        } else if (w == 'and' && numFlags.contains('n') && result.isNotEmpty) {
          final last = result.last;
          result[result.length - 1] = ('${last.$1}ən', last.$2);
        }
      }
    }

    if (_isDigit(word) && _ordinals.contains(suffix)) {
      extendNum(num2wordsOrdinal(BigInt.parse(word)), escape: true);
    } else if (result.isEmpty &&
        word.length == 4 &&
        !_currencies.containsKey(currency) &&
        _isDigit(word)) {
      extendNum(num2wordsYear(int.parse(word)), escape: true);
    } else if (!isHead && !word.contains('.')) {
      final num = word.replaceAll(',', '');
      if (num[0] == '0' || num.length > 3) {
        for (final n in _chars(num)) {
          extendNum(n, first: false);
        }
      } else if (num.length == 3 && !num.endsWith('00')) {
        extendNum(num[0]);
        if (num[1] == '0') {
          result.add(lookup('O', null, -2, null));
          extendNum(num[2], first: false);
        } else {
          extendNum(num.substring(1), first: false);
        }
      } else {
        extendNum(num);
      }
    } else if ('.'.allMatches(word).length > 1 || !isHead) {
      var first = true;
      for (final num in word.replaceAll(',', '').split('.')) {
        if (num.isEmpty) {
          // pass
        } else if (num[0] == '0' ||
            (num.length != 2 && _chars(num).skip(1).any((n) => n != '0'))) {
          for (final n in _chars(num)) {
            extendNum(n, first: false);
          }
        } else {
          extendNum(num, first: first);
        }
        first = false;
      }
    } else if (_currencies.containsKey(currency) && isCurrency(word)) {
      final units = _currencies[currency]!;
      final parts = word.replaceAll(',', '').split('.');
      var pairs = <(int, String)>[
        for (var i = 0; i < parts.length && i < 2; i++)
          (
            parts[i].isEmpty ? 0 : int.parse(parts[i]),
            i == 0 ? units.$1 : units.$2,
          ),
      ];
      if (pairs.length > 1) {
        if (pairs[1].$1 == 0) {
          pairs = pairs.sublist(0, 1);
        } else if (pairs[0].$1 == 0) {
          pairs = pairs.sublist(1);
        }
      }
      for (var i = 0; i < pairs.length; i++) {
        final (num, unit) = pairs[i];
        if (i > 0) result.add(lookup('and', null, null, null));
        extendNum('$num', first: i == 0);
        result.add(
          num.abs() != 1 && unit != 'pence'
              ? stemS('${unit}s', null, null, null)
              : lookup(unit, null, null, null),
        );
      }
    } else {
      if (_isDigit(word)) {
        word = num2wordsCardinal(BigInt.parse(word));
      } else if (!word.contains('.')) {
        final n = BigInt.parse(word.replaceAll(',', ''));
        word = _ordinals.contains(suffix)
            ? num2wordsOrdinal(n)
            : num2wordsCardinal(n);
      } else {
        word = word.replaceAll(',', '');
        if (word[0] == '.') {
          word =
              'point ${_chars(word.substring(1)).map((n) => num2wordsCardinal(BigInt.parse(n))).join(' ')}';
        } else {
          word = num2wordsFloat(double.parse(word));
        }
      }
      extendNum(word, escape: true);
    }
    if (result.isEmpty) return _none;
    final joined = result.map((p) => p.$1).join(' ');
    final rating = result.map((p) => p.$2 ?? 0).reduce((a, b) => a < b ? a : b);
    if (suffix == 's' || suffix == "'s") return (_s(joined), rating);
    if (suffix == 'ed' || suffix == "'d") return (_ed(joined), rating);
    if (suffix == 'ing') return (_ing(joined), rating);
    return (joined, rating);
  }

  String? appendCurrency(String? ps, String? currency) {
    if (currency == null || currency.isEmpty) return ps;
    final c = _currencies[currency];
    final name = c == null ? null : stemS('${c.$1}s', null, null, null).$1;
    return name != null && name.isNotEmpty ? '$ps $name' : ps;
  }

  static bool isNumber(String word, bool isHead) {
    if (!_chars(word).any(_isDigit)) return false;
    const suffixes = ['ing', "'d", 'ed', "'s", 'st', 'nd', 'rd', 'th', 's'];
    for (final s in suffixes) {
      if (word.endsWith(s)) {
        word = word.substring(0, word.length - s.length);
        break;
      }
    }
    final c = _chars(word);
    for (var i = 0; i < c.length; i++) {
      if (!(_isDigit(c[i]) ||
          c[i] == ',' ||
          c[i] == '.' ||
          (isHead && i == 0 && c[i] == '-'))) {
        return false;
      }
    }
    return true;
  }

  MisakiPs call(MToken tk, TokenContext ctx) {
    var word = (tk.alias ?? tk.text)
        .replaceAll('\u2018', "'")
        .replaceAll('\u2019', "'");
    word = _nfkcLite(word);
    final double? stress = _isLower(word)
        ? null
        : (_isUpper(word) ? _capStresses.$2 : _capStresses.$1);
    final (ps, rating) = getWord(word, tk.tag, stress, ctx);
    if (ps != null) {
      return (applyStress(appendCurrency(ps, tk.currency), tk.stress), rating);
    } else if (isNumber(word, tk.isHead)) {
      final (nps, nrating) = getNumber(
        word,
        tk.currency,
        tk.isHead,
        tk.numFlags,
      );
      return (applyStress(nps, tk.stress), nrating);
    }
    return _none;
  }
}

// ---------------------------------------------------------------------------
// G2P pipeline (everything after spaCy).

/// Output of [MisakiG2P.preprocess]: link-markup-free text, whitespace
/// tokens, and features keyed by whitespace-token index.
typedef MisakiPreprocessed = ({
  String text,
  List<String> tokens,
  Map<int, Object> features,
});

class MisakiG2P {
  MisakiG2P({
    required this.lexicon,
    this.unk = '❓',
    this.version,
    this.fallback,
  });

  /// Called for words the lexicon cannot pronounce (misaki main uses a small
  /// BART model; see `MisakiFallbackFfi`). Null leaves them as [unk].
  final MisakiFallback? fallback;

  final MisakiLexicon lexicon;

  /// Emitted for words with no pronunciation. Kokoro's pipeline uses ''.
  final String unk;

  /// misaki model version; anything but '2.0' maps ɾ->T and ʔ->t (Kokoro 1.0).
  final String? version;

  /// Parses `[text](/phonemes/)`, `[text](+1)` stress, and `[text](#flags#)`.
  static MisakiPreprocessed preprocess(String text) {
    final result = StringBuffer();
    final tokens = <String>[];
    final features = <int, Object>{};
    var lastEnd = 0;
    text = _lstripSpace(text);
    List<String> split(String s) =>
        s.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    for (final m in _linkRe.allMatches(text)) {
      result.write(text.substring(lastEnd, m.start));
      tokens.addAll(split(text.substring(lastEnd, m.start)));
      var f = m[2]!;
      Object? feature;
      final unsigned = f.startsWith('-') || f.startsWith('+')
          ? f.substring(1)
          : f;
      if (_isDigit(unsigned)) {
        feature = double.parse(f);
      } else if (f == '0.5' || f == '+0.5') {
        feature = 0.5;
      } else if (f == '-0.5') {
        feature = -0.5;
      } else if (f.length > 1 && f.startsWith('/') && f.endsWith('/')) {
        feature = f[0] + _rstrip(f.substring(1), '/');
      } else if (f.length > 1 && f.startsWith('#') && f.endsWith('#')) {
        feature = f[0] + _rstrip(f.substring(1), '#');
      }
      if (feature != null) features[tokens.length] = feature;
      result.write(m[1]);
      tokens.add(m[1]!);
      lastEnd = m.end;
    }
    if (lastEnd < text.length) {
      result.write(text.substring(lastEnd));
      tokens.addAll(split(text.substring(lastEnd)));
    }
    return (text: result.toString(), tokens: tokens, features: features);
  }

  /// Applies [features] to tokenizer output. [offsets] are each token's start
  /// index in the preprocessed text; alignment to whitespace tokens is by
  /// character overlap, like spaCy's `Alignment.from_strings`.
  static void applyFeatures(
    List<MToken> tokens,
    List<int> offsets,
    String text,
    List<String> wsTokens,
    Map<int, Object> features,
  ) {
    if (features.isEmpty) return;
    // Character span of each whitespace token in text.
    final spans = <(int, int)>[];
    var pos = 0;
    for (final t in wsTokens) {
      final start = text.indexOf(t, pos);
      spans.add((start, start + t.length));
      pos = start + t.length;
    }
    // Flattened y2x: for each token, the whitespace tokens it overlaps.
    final y2x = <int>[];
    for (var j = 0; j < tokens.length; j++) {
      final a = offsets[j], b = offsets[j] + tokens[j].text.length;
      if (tokens[j].text.trim().isEmpty) continue;
      for (var x = 0; x < spans.length; x++) {
        if (spans[x].$1 < b && a < spans[x].$2) y2x.add(x);
      }
    }
    for (final MapEntry(key: k, value: v) in features.entries) {
      var i = 0;
      for (var j = 0; j < y2x.length; j++) {
        if (y2x[j] != k) continue;
        if (j < tokens.length) {
          final tk = tokens[j];
          if (v is double) {
            tk.stress = v;
          } else if (v is String && v.startsWith('/')) {
            tk.isHead = i == 0;
            tk.phonemes = i == 0 ? v.replaceFirst(RegExp(r'^/+'), '') : '';
            tk.rating = 5;
          } else if (v is String && v.startsWith('#')) {
            tk.numFlags = v.replaceFirst(RegExp(r'^#+'), '');
          }
        }
        i++;
      }
    }
  }

  List<MToken> foldLeft(List<MToken> tokens) {
    final result = <MToken>[];
    for (final tk in tokens) {
      if (result.isNotEmpty && !tk.isHead) {
        result.add(mergeTokens([result.removeLast(), tk], unk: unk));
      } else {
        result.add(tk);
      }
    }
    return result;
  }

  /// Returns a list whose items are either [MToken] or `List<MToken>`.
  static List<Object> retokenize(List<MToken> tokens) {
    final words = <Object>[];
    String? currency;
    for (var i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      final List<MToken> tks;
      if (token.alias == null && token.phonemes == null) {
        tks = [
          for (final t in subtokenize(token.text))
            MToken(
              text: t,
              tag: token.tag,
              whitespace: '',
              numFlags: token.numFlags,
              stress: token.stress,
            ),
        ];
      } else {
        tks = [token];
      }
      if (tks.isEmpty) continue;
      tks.last.whitespace = token.whitespace;
      for (var j = 0; j < tks.length; j++) {
        final tk = tks[j];
        if (tk.alias != null || tk.phonemes != null) {
          // pass
        } else if (tk.tag == r'$' && _currencies.containsKey(tk.text)) {
          currency = tk.text;
          tk.phonemes = '';
          tk.rating = 4;
        } else if (tk.tag == ':' && (tk.text == '-' || tk.text == '–')) {
          tk.phonemes = '—';
          tk.rating = 3;
        } else if (_punctTags.contains(tk.tag) &&
            !_chars(tk.text).every((c) {
              final o = c.toLowerCase().codeUnitAt(0);
              return 97 <= o && o <= 122;
            })) {
          tk.phonemes =
              _punctTagPhonemes[tk.tag] ??
              _chars(tk.text).where(_puncts.contains).join();
          tk.rating = 4;
        } else if (currency != null) {
          if (tk.tag != 'CD') {
            currency = null;
          } else if (j + 1 == tks.length &&
              (i + 1 == tokens.length || tokens[i + 1].tag != 'CD')) {
            tk.currency = currency;
          }
        } else if (0 < j &&
            j < tks.length - 1 &&
            tk.text == '2' &&
            _isAlpha(
              tks[j - 1].text[tks[j - 1].text.length - 1] + tks[j + 1].text[0],
            )) {
          tk.alias = 'to';
        }
        if (tk.alias != null || tk.phonemes != null) {
          words.add(tk);
        } else if (words.isNotEmpty &&
            words.last is List<MToken> &&
            (words.last as List<MToken>).last.whitespace.isEmpty) {
          tk.isHead = false;
          (words.last as List<MToken>).add(tk);
        } else {
          words.add(tk.whitespace.isNotEmpty ? tk : <MToken>[tk]);
        }
      }
    }
    return [
      for (final w in words)
        if (w is List<MToken> && w.length == 1) w.first else w,
    ];
  }

  static TokenContext tokenContext(TokenContext ctx, String? ps, MToken token) {
    var vowel = ctx.futureVowel;
    if (ps != null && ps.isNotEmpty) {
      for (final c in _chars(ps)) {
        if (_vowels.contains(c) ||
            _consonants.contains(c) ||
            _nonQuotePuncts.contains(c)) {
          vowel = _nonQuotePuncts.contains(c) ? null : _vowels.contains(c);
          break;
        }
      }
    }
    final t = token.text;
    final futureTo =
        t == 'to' ||
        t == 'To' ||
        (t == 'TO' && (token.tag == 'TO' || token.tag == 'IN'));
    return TokenContext(futureVowel: vowel, futureTo: futureTo);
  }

  static void resolveTokens(List<MToken> tokens) {
    final text = StringBuffer();
    for (var i = 0; i < tokens.length - 1; i++) {
      text
        ..write(tokens[i].text)
        ..write(tokens[i].whitespace);
    }
    text.write(tokens.last.text);
    final t = text.toString();
    final classes = <int>{
      for (final c in _chars(t))
        if (!_subtokenJunks.contains(c))
          _isAlpha(c) ? 0 : (_isDigit(c) ? 1 : 2),
    };
    final prespace = t.contains(' ') || t.contains('/') || classes.length > 1;
    for (var i = 0; i < tokens.length; i++) {
      final tk = tokens[i];
      if (tk.phonemes == null) {
        if (i == tokens.length - 1 &&
            _nonQuotePuncts.contains(tk.text) &&
            tk.text.isNotEmpty &&
            _chars(tk.text).length == 1) {
          tk.phonemes = tk.text;
          tk.rating = 3;
        } else if (_chars(tk.text).every(_subtokenJunks.contains)) {
          tk.phonemes = '';
          tk.rating = 3;
        }
      } else if (i > 0) {
        tk.prespace = prespace;
      }
    }
    if (prespace) return;
    final indices = <(bool, int, int)>[
      for (var i = 0; i < tokens.length; i++)
        if (tokens[i].phonemes != null && tokens[i].phonemes!.isNotEmpty)
          (
            tokens[i].phonemes!.contains(_primaryStress),
            stressWeight(tokens[i].phonemes),
            i,
          ),
    ];
    if (indices.length == 2 && _chars(tokens[indices[0].$3].text).length == 1) {
      final i = indices[1].$3;
      tokens[i].phonemes = applyStress(tokens[i].phonemes, -0.5);
      return;
    } else if (indices.length < 2 ||
        indices.where((e) => e.$1).length <= (indices.length + 1) ~/ 2) {
      return;
    }
    indices.sort((a, b) {
      if (a.$1 != b.$1) return a.$1 ? 1 : -1;
      if (a.$2 != b.$2) return a.$2.compareTo(b.$2);
      return a.$3.compareTo(b.$3);
    });
    for (final (_, _, i) in indices.take(indices.length ~/ 2)) {
      tokens[i].phonemes = applyStress(tokens[i].phonemes, -0.5);
    }
  }

  /// Runs misaki on tokenizer output (spaCy-style tokens with Penn tags).
  ///
  /// Returns the phoneme string and the merged tokens.
  (String, List<MToken>) phonemizeTokens(List<MToken> input) {
    final tokens = retokenize(foldLeft(input));
    var ctx = const TokenContext();
    for (var i = tokens.length - 1; i >= 0; i--) {
      final item = tokens[i];
      if (item is MToken) {
        if (item.phonemes == null) {
          final (ps, rating) = lexicon.call(item, ctx);
          item
            ..phonemes = ps
            ..rating = rating;
        }
        if (item.phonemes == null && fallback != null) {
          final (ps, rating) = fallback!(item);
          item
            ..phonemes = ps
            ..rating = rating;
        }
        ctx = tokenContext(ctx, item.phonemes, item);
        continue;
      }
      final w = item as List<MToken>;
      var left = 0, right = w.length;
      var shouldFallback = false;
      while (left < right) {
        final slice = w.sublist(left, right);
        MToken? tk;
        if (!slice.any((t) => t.alias != null || t.phonemes != null)) {
          tk = mergeTokens(slice);
        }
        final (ps, rating) = tk == null ? _none : lexicon.call(tk, ctx);
        if (ps != null) {
          w[left]
            ..phonemes = ps
            ..rating = rating;
          for (final x in w.sublist(left + 1, right)) {
            x.phonemes = '';
          }
          ctx = tokenContext(ctx, ps, tk!);
          right = left;
          left = 0;
        } else if (left + 1 < right) {
          left++;
        } else {
          right--;
          final t = w[right];
          if (t.phonemes == null) {
            if (_chars(t.text).every(_subtokenJunks.contains)) {
              t.phonemes = '';
              t.rating = 3;
            } else if (fallback != null) {
              shouldFallback = true;
              break;
            }
          }
          left = 0;
        }
      }
      if (shouldFallback) {
        final (ps, rating) = fallback!(mergeTokens(w));
        w[0]
          ..phonemes = ps
          ..rating = rating;
        for (final x in w.skip(1)) {
          x
            ..phonemes = ''
            ..rating = rating;
        }
      } else {
        resolveTokens(w);
      }
    }
    final merged = [
      for (final t in tokens)
        t is List<MToken> ? mergeTokens(t, unk: unk) : t as MToken,
    ];
    if (version != '2.0') {
      for (final tk in merged) {
        final p = tk.phonemes;
        if (p != null && p.isNotEmpty) {
          tk.phonemes = p.replaceAll('ɾ', 'T').replaceAll('ʔ', 't');
        }
      }
    }
    final out = StringBuffer();
    for (final tk in merged) {
      out
        ..write(tk.phonemes ?? unk)
        ..write(tk.whitespace);
    }
    return (out.toString(), merged);
  }
}
