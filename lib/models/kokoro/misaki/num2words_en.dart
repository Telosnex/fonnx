/// English number wording for the misaki pipeline.
///
/// Groups decimal digits in threes and renders each group independently.
/// No num2words source or recursive card/merge implementation is used here.
library;

const List<String> _highNumwords = [
  'million',
  'billion',
  'trillion',
  'quadrillion',
  'quintillion',
  'sextillion',
  'septillion',
  'octillion',
  'nonillion',
  'decillion',
  'undecillion',
  'duodecillion',
  'tredecillion',
  'quattuordecillion',
  'quindecillion',
  'sexdecillion',
  'septdecillion',
  'octodecillion',
  'novemdecillion',
  'vigintillion',
  'unvigintillion',
  'duovigintillion',
  'trevigintillion',
  'quattuorvigintillion',
  'quinvigintillion',
  'sexvigintillion',
  'septvigintillion',
  'octovigintillion',
  'novemvigintillion',
  'trigintillion',
  'untrigintillion',
  'duotrigintillion',
  'tretrigintillion',
  'quattuortrigintillion',
  'quintrigintillion',
  'sextrigintillion',
  'septtrigintillion',
  'octotrigintillion',
  'novemtrigintillion',
  'quadragintillion',
  'unquadragintillion',
  'duoquadragintillion',
  'trequadragintillion',
  'quattuorquadragintillion',
  'quinquadragintillion',
  'sexquadragintillion',
  'septquadragintillion',
  'octoquadragintillion',
  'novemquadragintillion',
  'quinquagintillion',
  'unquinquagintillion',
  'duoquinquagintillion',
  'trequinquagintillion',
  'quattuorquinquagintillion',
  'quinquinquagintillion',
  'sexquinquagintillion',
  'septquinquagintillion',
  'octoquinquagintillion',
  'novemquinquagintillion',
  'sexagintillion',
  'unsexagintillion',
  'duosexagintillion',
  'tresexagintillion',
  'quattuorsexagintillion',
  'quinsexagintillion',
  'sexsexagintillion',
  'septsexagintillion',
  'octosexagintillion',
  'novemsexagintillion',
  'septuagintillion',
  'unseptuagintillion',
  'duoseptuagintillion',
  'treseptuagintillion',
  'quattuorseptuagintillion',
  'quinseptuagintillion',
  'sexseptuagintillion',
  'septseptuagintillion',
  'octoseptuagintillion',
  'novemseptuagintillion',
  'octogintillion',
  'unoctogintillion',
  'duooctogintillion',
  'treoctogintillion',
  'quattuoroctogintillion',
  'quinoctogintillion',
  'sexoctogintillion',
  'septoctogintillion',
  'octooctogintillion',
  'novemoctogintillion',
  'nonagintillion',
  'unnonagintillion',
  'duononagintillion',
  'trenonagintillion',
  'quattuornonagintillion',
  'quinnonagintillion',
  'sexnonagintillion',
  'septnonagintillion',
  'octononagintillion',
  'novemnonagintillion',
  'centillion',
];

const _small = [
  'zero',
  'one',
  'two',
  'three',
  'four',
  'five',
  'six',
  'seven',
  'eight',
  'nine',
  'ten',
  'eleven',
  'twelve',
  'thirteen',
  'fourteen',
  'fifteen',
  'sixteen',
  'seventeen',
  'eighteen',
  'nineteen',
];
const _tens = [
  '',
  '',
  'twenty',
  'thirty',
  'forty',
  'fifty',
  'sixty',
  'seventy',
  'eighty',
  'ninety',
];

String _group(int value) {
  if (value < 20) return _small[value];
  if (value < 100) {
    return _tens[value ~/ 10] +
        (value % 10 == 0 ? '' : '-${_small[value % 10]}');
  }
  return '${_small[value ~/ 100]} hundred${value % 100 == 0 ? '' : ' and ${_group(value % 100)}'}';
}

String num2wordsCardinal(BigInt value) {
  if (value.isNegative) return 'minus ${num2wordsCardinal(-value)}';
  final digits = value.toString();
  if (digits.length > 306) {
    throw ArgumentError.value(value, 'value', 'Too large');
  }
  final groups = <int>[];
  for (var end = digits.length; end > 0; end -= 3) {
    groups.add(int.parse(digits.substring(end < 3 ? 0 : end - 3, end)));
  }
  final result = StringBuffer();
  for (var index = groups.length - 1; index >= 0; index--) {
    final group = groups[index];
    if (group == 0) continue;
    if (result.isNotEmpty) {
      result.write(index == 0 && group < 100 ? ' and ' : ', ');
    }
    result.write(_group(group));
    if (index == 1) result.write(' thousand');
    if (index > 1) result.write(' ${_highNumwords[index - 2]}');
  }
  return result.isEmpty ? 'zero' : result.toString();
}

String num2wordsOrdinal(BigInt value) {
  if (value.isNegative) {
    throw ArgumentError.value(value, 'value', 'Negative ordinal');
  }
  final cardinal = num2wordsCardinal(value);
  final start = cardinal.lastIndexOf(RegExp(r'[ -]')) + 1;
  final ending = cardinal.substring(start);
  const exceptions = {
    'one': 'first',
    'two': 'second',
    'three': 'third',
    'five': 'fifth',
    'eight': 'eighth',
    'nine': 'ninth',
    'twelve': 'twelfth',
  };
  final ordinal =
      exceptions[ending] ??
      (ending.endsWith('y')
          ? '${ending.substring(0, ending.length - 1)}ieth'
          : '${ending}th');
  return cardinal.substring(0, start) + ordinal;
}

String num2wordsYear(int value) {
  if (value < 0) return '${num2wordsYear(-value)} BC';
  final century = value ~/ 100;
  final year = value % 100;
  if (century == 0 || century >= 100 || (century % 10 == 0 && year < 10)) {
    return num2wordsCardinal(BigInt.from(value));
  }
  final suffix = year == 0
      ? 'hundred'
      : year < 10
      ? 'oh-${_small[year]}'
      : _group(year);
  return '${_group(century)} $suffix';
}

String num2wordsFloat(double value) {
  if (!value.isFinite) throw ArgumentError.value(value, 'value', 'Not finite');
  final whole = value.truncateToDouble();
  if (whole == value) return num2wordsCardinal(BigInt.from(value));
  // Expand the shortest decimal representation, without binary rounding of
  // the fractional part. Keep the reference's unsigned wording for -0.x.
  final components = value.abs().toString().toLowerCase().split('e');
  final mantissa = components.first.split('.');
  final digits = mantissa.join();
  final point =
      mantissa.first.length +
      (components.length == 1 ? 0 : int.parse(components[1]));
  final fraction = point < 0
      ? '${'0' * -point}$digits'
      : digits.substring(point);
  return '${num2wordsCardinal(BigInt.from(whole))} point '
      '${fraction.split('').map((digit) => _small[int.parse(digit)]).join(' ')}';
}
