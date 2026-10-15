/// Small, explicit English speech rewrites before misaki. Pronunciation
/// overrides remain untouched; callers can disable normalization entirely.
String normalizeKokoroEnglish(String text) {
  final overrides = <String>[];
  text = text.replaceAllMapped(RegExp(r'\[[^\]]+\]\([^)]*\)'), (m) {
    overrides.add(m[0]!);
    return '\uE000${overrides.length - 1}\uE001';
  });
  text = text.replaceAllMapped(
    RegExp(r'\b([\w.+-]+)@([\w.-]+\.[a-zA-Z]{2,})\b'),
    (m) => '${_address(m[1]!)} at ${_address(m[2]!)}',
  );
  text = text.replaceAllMapped(RegExp(r'https?://[^\s<>]+'), (m) {
    var url = m[0]!.replaceFirst(RegExp(r'^https?://'), '');
    var punctuation = '';
    while (url.isNotEmpty && '.,!?;'.contains(url[url.length - 1])) {
      punctuation = url[url.length - 1] + punctuation;
      url = url.substring(0, url.length - 1);
    }
    return _address(url) + punctuation;
  });
  text = text.replaceAllMapped(RegExp(r'\b([01]?\d|2[0-3]):([0-5]\d)\b'), (m) {
    final minute = int.parse(m[2]!);
    return '${int.parse(m[1]!)} ${minute == 0
        ? "o'clock"
        : minute < 10
        ? 'oh $minute'
        : '$minute'}';
  });
  const units = {
    'kg': 'kilograms',
    'km': 'kilometers',
    'GB': 'gigabytes',
    'MB': 'megabytes',
    'cm': 'centimeters',
    'mm': 'millimeters',
    'Hz': 'hertz',
  };
  text = text.replaceAllMapped(
    RegExp(r'\b(\d+(?:\.\d+)?)(kg|km|GB|MB|cm|mm|Hz)\b'),
    (m) => '${m[1]} ${units[m[2]]}',
  );
  text = text.replaceAll('&', ' and ').replaceAll('°', ' degrees ');
  return text.replaceAllMapped(
    RegExp('\uE000(\\d+)\uE001'),
    (m) => overrides[int.parse(m[1]!)],
  );
}

String _address(String value) => value
    .replaceAll('.', ' dot ')
    .replaceAll('/', ' slash ')
    .replaceAll('-', ' dash ')
    .replaceAll('_', ' underscore ')
    .replaceAll('+', ' plus ');
