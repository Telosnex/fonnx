import 'package:fonnx/third_party/diacritic/diacritic.dart';
import 'package:fonnx/tokenizers/embedding.dart';

class WordpieceTokenizer {
  final Map<String, int> encoder;
  final List<String> decoder;
  final String unkString;
  final int startToken;
  final int endToken;
  final int unkToken;
  final int maxInputTokens;
  final int maxInputCharsPerWord;

  // Cache for normalized words
  final Map<String, String> _normalizedCache = {};

  // Cache for tokenized words
  final Map<String, List<int>> _tokenCache = {};

  // Separate maps for prefix and wordpiece tokens
  late final Map<String, int> _prefixTokens;
  late final Map<String, int> _wordpieceTokens;

  WordpieceTokenizer({
    required this.encoder,
    required this.decoder,
    required this.unkString,
    required this.startToken,
    required this.endToken,
    required this.unkToken,
    required this.maxInputTokens,
    required this.maxInputCharsPerWord,
  }) {
    // Split encoder into prefix and wordpiece maps
    _prefixTokens = {};
    _wordpieceTokens = {};

    for (var entry in encoder.entries) {
      if (entry.key.startsWith('##')) {
        _wordpieceTokens[entry.key.substring(2)] = entry.value;
      } else {
        _prefixTokens[entry.key] = entry.value;
      }
    }
  }

  bool _isNoSpaceLanguageChar(int codeUnit) {
    return (0x4E00 <= codeUnit && codeUnit <= 0x9FFF) ||
        (0x3400 <= codeUnit && codeUnit <= 0x4DBF) ||
        (0x20000 <= codeUnit && codeUnit <= 0x2A6DF) ||
        (0x2A700 <= codeUnit && codeUnit <= 0x2B73F) ||
        (0x2B740 <= codeUnit && codeUnit <= 0x2B81F) ||
        (0x2B920 <= codeUnit && codeUnit <= 0x2CEAF) ||
        (0xF900 <= codeUnit && codeUnit <= 0xFAFF) ||
        (0x2F800 <= codeUnit && codeUnit <= 0x2FA1F) ||
        (0x3040 <= codeUnit && codeUnit <= 0x309F) ||
        (0x30A0 <= codeUnit && codeUnit <= 0x30FF);
  }

  List<int> _tokenizeWord(String word) {
    // Check cache first
    final cached = _tokenCache[word];
    if (cached != null) return cached;

    final wordLength = word.length;
    if (wordLength == 0) return [unkToken];

    final tokens = <int>[];
    var start = 0;

    while (start < wordLength) {
      var found = false;
      var end = wordLength;

      // First try exact prefix match for first token
      if (start == 0) {
        final prefixToken = _prefixTokens[word];
        if (prefixToken != null) {
          _tokenCache[word] = [prefixToken];
          return [prefixToken];
        }
      }

      // Try wordpiece matches
      while (start < end) {
        final piece = word.substring(start, end);
        final token = start == 0
            ? _prefixTokens[piece]
            : _wordpieceTokens[piece];

        if (token != null) {
          tokens.add(token);
          start = end;
          found = true;
          break;
        }

        if (end - start == 1 &&
            _isNoSpaceLanguageChar(word.codeUnitAt(start))) {
          tokens.add(unkToken);
          start = end;
          found = true;
          break;
        }
        end--;
      }

      if (!found) {
        _tokenCache[word] = [unkToken];
        return [unkToken];
      }
    }

    _tokenCache[word] = List.of(tokens);
    return tokens;
  }

  List<TextAndTokens> tokenize(String text, {int? maxTokens}) {
    final max = maxTokens ?? maxInputTokens;
    text = text.trim();
    if (text.isEmpty) {
      return [
        TextAndTokens(text: '', tokens: [startToken, endToken]),
      ];
    }

    final words = text.split(RegExp(r'\s+'));
    final allOutputTokens = <List<int>>[];
    final allOutputStrings = <String>[];

    var currentTokens = <int>[startToken];
    var currentStrings = <String>[];

    for (final word in words) {
      if (word.length > maxInputCharsPerWord) continue;

      // Get or compute normalized word
      final normalizedWord = _normalizedCache[word] ??= removeDiacritics(
        word.toLowerCase(),
      );
      final wordTokens = _tokenizeWord(normalizedWord);

      if (currentTokens.length + wordTokens.length >= max - 1) {
        // Finalize current chunk
        currentTokens.add(endToken);
        allOutputTokens.add(currentTokens);
        allOutputStrings.add(currentStrings.join(' '));

        // Start new chunk
        currentTokens = <int>[startToken, ...wordTokens];
        currentStrings = [word];
      } else {
        currentTokens.addAll(wordTokens);
        currentStrings.add(word);
      }
    }

    // Add final chunk
    currentTokens.add(endToken);
    allOutputTokens.add(currentTokens);
    allOutputStrings.add(currentStrings.join(' '));

    return List<TextAndTokens>.generate(
      allOutputStrings.length,
      (i) =>
          TextAndTokens(text: allOutputStrings[i], tokens: allOutputTokens[i]),
    );
  }

  String detokenize(List<int> tokens) {
    final strings = <String>[];
    bool processedFirstNonstartToken = false;
    for (var (index, token) in tokens.indexed) {
      if (token == endToken) {
        break;
      }
      if (token == startToken) {
        continue;
      }
      final decodedString = decoder[token];
      if (decodedString.startsWith('##')) {
        strings.add(decodedString.substring(2));
      } else {
        if (index > 0 && processedFirstNonstartToken) {
          strings.add(' $decodedString');
        } else {
          strings.add(decodedString);
        }
      }
      processedFirstNonstartToken = true;
    }
    return strings.join('');
  }

  void clearCaches() {
    _normalizedCache.clear();
    _tokenCache.clear();
  }
}
