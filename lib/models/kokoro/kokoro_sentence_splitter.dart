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

/// Splits [text] into units that end at sentence marks.
///
/// With `finalInput: false`, more text can follow. A mark is not decided
/// until the characters that decide it exist: a closer can follow a mark at
/// the end of [text], and the word after `. ` is not known yet. Such a mark
/// stays in the remainder. So for any split of a text into fragments, a
/// caller that splits `remainder + fragment` each time gets the same units
/// as one call with the whole text.
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
  // Where the text in [pending] starts.
  var pendingStart = 0;
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
    // Only whitespace and closers follow, so no later mark exists.
    if (!finalInput &&
        (end == chars.length || (c == '.' && next == chars.length))) {
      break;
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
      if (pending.isEmpty) pendingStart = start;
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
  if (pending.isNotEmpty) {
    // More text can follow, so keep the source text. A later call splits
    // and holds it again in the same way.
    tail = finalInput
        ? (tail.isEmpty ? pending : '$pending $tail')
        : chars.sublist(pendingStart).join();
  }
  if (finalInput) {
    tail = _trim(tail);
    if (tail.isNotEmpty) units.add(tail);
    tail = '';
  }
  return KokoroSentenceSplit(units, tail);
}

/// Every mark that can end a unit, with or without `splitOnColon`.
const _marks = '.!?…:。！？｡؟۔।॥።։';

/// Whether `kokoroSplitSentences(remainder + added)` can give a unit, when
/// [remainder] is the remainder of an earlier split with `finalInput: false`.
/// If false, the split gives no units, so a streaming caller can skip it.
/// True can be a false alarm.
///
/// A unit ends only at a mark. A mark in [remainder] that did not split
/// cannot split later, unless only whitespace and closers follow it.
bool kokoroSplitMayChange(String remainder, String added) {
  for (var i = 0; i < added.length; i++) {
    if (_marks.contains(added[i])) return true;
  }
  var end = remainder.length;
  while (end > 0 &&
      (_space(remainder[end - 1]) || _closers.contains(remainder[end - 1]))) {
    end--;
  }
  return end > 0 && _marks.contains(remainder[end - 1]);
}
