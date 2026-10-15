// English port of Moonshine sentence-splitter.cpp at
// 234f60faa0eb388b01cdf7e60aca232af37aefda. MIT notice: third_party/moonshine_LICENSE.txt.
//
// Changes from Moonshine, so that one unmatched quote or bracket cannot stop
// all later splits (seen in scanned books):
// - An open quote or bracket is a flag, not a count. Any closer clears it.
// - ’ also closes a quote. As an apostrophe it only clears the flag early.
// - The flag stops holding sentence ends after [openLimit] characters.
//
// A spaced ellipsis (". . .") is one mark, like "...". Moonshine splits it
// into sentences of one period each.

class KokoroSentenceSplit {
  const KokoroSentenceSplit(this.units, this.remainder);
  final List<String> units;
  final String remainder;
}

final _letter = RegExp(r'^\p{L}$', unicode: true);
final _lower = RegExp(r'^\p{Ll}$', unicode: true);
const _abbreviations = {
  'dr',
  'mr',
  'mrs',
  'ms',
  'mx',
  'prof',
  'st',
  'jr',
  'sr',
  'vs',
  'etc',
  'al',
  'cf',
  'inc',
  'ltd',
  'co',
  'corp',
  'dept',
  'est',
  'fig',
  'no',
  'op',
  'p',
  'pp',
  'vol',
  'ed',
  'eds',
  'rev',
  'hon',
  'gov',
  'sen',
  'rep',
  'sgt',
  'capt',
  'lt',
  'col',
  'gen',
  'ave',
  'blvd',
  'approx',
};
const _closers = {
  ')',
  ']',
  '}',
  '"',
  "'",
  '»',
  '’',
  '”',
  '‘',
  '」',
  '』',
  '）',
  '］',
};
int _bracket(String c) => '([{（［'.contains(c)
    ? 1
    : ')]}）］'.contains(c)
    ? -1
    : 0;
int _quote(String c) => '“«「『'.contains(c)
    ? 1
    : '”»」』’'.contains(c)
    ? -1
    : 0;
bool _space(String c) => ' \t\n\r\v\f'.contains(c);
String _trim(String s) =>
    s.replaceAll(RegExp(r'^[ \t\n\r\v\f]+|[ \t\n\r\v\f]+$'), '');

KokoroSentenceSplit kokoroSplitSentences(
  String text, {
  bool finalInput = false,
  bool splitOnColon = true,
  int minCodepoints = 0,
  int openLimit = 500,
}) {
  final chars = text.runes.map(String.fromCharCode).toList();
  final units = <String>[];
  var start = 0, i = 0, brackets = 0, quotes = 0;
  var pending = '';
  var bracketAt = 0, quoteAt = 0;
  while (i < chars.length) {
    final c = chars[i];
    if (_bracket(c) > 0 && brackets == 0) bracketAt = i;
    if (_quote(c) > 0 && quotes == 0) quoteAt = i;
    brackets = (brackets + _bracket(c)).clamp(0, 1);
    quotes = (quotes + _quote(c)).clamp(0, 1);
    final ambiguous = '.!?…'.contains(c) || (splitOnColon && c == ':');
    final certain = '。！？｡؟۔।॥።։'.contains(c);
    if (!ambiguous && !certain) {
      i++;
      continue;
    }
    var end = i + 1, closedBrackets = 0, closedQuotes = 0;
    while (end < chars.length && _closers.contains(chars[end])) {
      closedBrackets += _bracket(chars[end]);
      closedQuotes += _quote(chars[end]);
      end++;
    }
    var next = end;
    while (next < chars.length && _space(chars[next])) {
      next++;
    }
    if (ambiguous) {
      if (next == end ||
          (c == '.' &&
              end == i + 1 &&
              next < chars.length &&
              chars[next] == '.')) {
        i++;
        continue;
      }
      if (c == '.') {
        var wordStart = i;
        while (wordStart > 0 && _letter.hasMatch(chars[wordStart - 1])) {
          wordStart--;
        }
        final word = chars
            .sublist(wordStart, i)
            .join()
            .replaceAllMapped(RegExp('[A-Z]'), (m) => m[0]!.toLowerCase());
        if (i - wordStart == 1 ||
            _abbreviations.contains(word) ||
            (next < chars.length && _lower.hasMatch(chars[next]))) {
          i++;
          continue;
        }
      }
    }
    if (brackets > 0 && i - bracketAt > openLimit) brackets = 0;
    if (quotes > 0 && i - quoteAt > openLimit) quotes = 0;
    if (brackets + closedBrackets > 0 || quotes + closedQuotes > 0) {
      i++;
      continue;
    }
    final piece = _trim(chars.sublist(start, end).join());
    if (piece.isNotEmpty) {
      final joined = pending.isEmpty ? piece : '$pending $piece';
      pending = '';
      if (minCodepoints > 0 && joined.runes.length < minCodepoints) {
        pending = joined;
      } else {
        units.add(joined);
      }
    }
    brackets = (brackets + closedBrackets).clamp(0, 1);
    quotes = (quotes + closedQuotes).clamp(0, 1);
    start = next;
    i = next;
  }
  var tail = chars
      .sublist(start)
      .join()
      .replaceFirst(RegExp(r'^[ \t\n\r\v\f]+'), '');
  if (pending.isNotEmpty) tail = tail.isEmpty ? pending : '$pending $tail';
  if (finalInput) {
    tail = _trim(tail);
    if (tail.isNotEmpty) units.add(tail);
    tail = '';
  }
  return KokoroSentenceSplit(units, tail);
}
