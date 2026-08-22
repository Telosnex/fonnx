import 'keyword_spotter.dart';

Future<KeywordSpotter> getKeywordSpotter({
  required KeywordSpotterBundle bundle,
  required List<KeywordPhrase> keywords,
  required int maxActivePaths,
  required int trailingBlankFrames,
}) =>
    throw UnsupportedError('Keyword spotting is unsupported on this platform');
