import 'package:fonnx/tokenizers/bert_vocab.dart';

class WordpieceTokenizer {
  final Map<String, int> encoder;
  final List<String> decoder;
  final String unkString;
  final int startToken;
  final int endToken;
  final int unkToken;
  final int maxInputTokens;
  final int maxInputCharsPerWord;

  const WordpieceTokenizer({
    required this.encoder,
    required this.decoder,
    required this.unkString,
    required this.startToken,
    required this.endToken,
    required this.unkToken,
    required this.maxInputTokens,
    required this.maxInputCharsPerWord,
  });

  static const WordpieceTokenizer _cachedBertTokenizer = WordpieceTokenizer(
    encoder: bertEncoder,
    decoder: bertDecoder,
    unkString: '[UNK]',
    unkToken: 100,
    startToken: 101,
    endToken: 102,
    maxInputTokens: 256,
    maxInputCharsPerWord: 100,
  );

  factory WordpieceTokenizer.bert() {
    return _cachedBertTokenizer;
  }

  /// Checks if the given code unit is a Chinese character, meaning, it
  /// represents a word and the tokenizer should treat it as such.
  ///
  /// This defines a "chinese character" as anything in the CJK Unicode block:
  ///   https://en.wikipedia.org/wiki/CJK_Unified_Ideographs_(Unicode_block)
  ///
  /// Note that the CJK Unicode block is NOT all Japanese and Korean characters,
  /// despite its name. The modern Korean Hangul alphabet is a different block,
  /// as is Japanese Hiragana and Katakana. Those alphabets are used to write
  /// space-separated words, so they are not treated specially and handled
  /// like for all of the other languages.
  bool _isChineseChar(int codeUnit) {
    // Comment and implementation patterned after https://github.com/huggingface/tokenizers/blob/0d8c57da48319a91fe9cd3e31a36b9bd29a8292c/tokenizers/src/normalizers/bert.rs#L36
    return (0x4E00 <= codeUnit && codeUnit <= 0x9FFF) ||
        (0x3400 <= codeUnit && codeUnit <= 0x4DBF) ||
        (0x20000 <= codeUnit && codeUnit <= 0x2A6DF) ||
        (0x2A700 <= codeUnit && codeUnit <= 0x2B73F) ||
        (0x2B740 <= codeUnit && codeUnit <= 0x2B81F) ||
        (0x2B920 <= codeUnit && codeUnit <= 0x2CEAF) ||
        (0xF900 <= codeUnit && codeUnit <= 0xFAFF) ||
        (0x2F800 <= codeUnit && codeUnit <= 0x2FA1F);
  }

  List<int> _createSubstrings(String text) {
    text = text.trim();
    if (text.isEmpty) {
      return [];
    }

    List<int> outputTokens = [startToken];

    List<String> words = text.split(RegExp(r'\s+')); // Split on whitespace
    for (final word in words) {
      // Convert to lowercase individual characters. Why lowercase? The BERT
      // vocabulary doesn't have tokens with uppercase English letters.
      List<String> characters = word.toLowerCase().split('');

      // If the word is too long, replace it with UNK token
      if (characters.length > maxInputCharsPerWord) {
        continue;
      }

      bool isBad = false;
      int start = 0;

      // This will hold the substrings for the current word.
      List<String> wordpieces = [];
      List<int> wordTokens = [];
      while (start < characters.length) {
        int end = characters.length;
        String? wordpiece;
        int? wordpieceToken;

        // Loop for finding the largest valid substring starting at the current
        // position
        while (start < end) {
          String substr = characters.sublist(start, end).join();

          // Append "##" in front of the substring if it's not at the start of
          // the token
          if (start > 0) {
            substr = "##$substr";
          }

          // Check if the substring exists in the vocabulary
          final token = encoder[substr];
          if (token != null) {
            // If substring is in vocabulary, store this substring
            wordpiece = substr;
            wordpieceToken = token;
            break;
          } else if ((end - start == 1) &&
              _isChineseChar(characters[start].codeUnitAt(0))) {
            // Chinese character without token? add UNK token. Essentially,
            // we are treating each Chinese character as a word. This matches
            // the character-based tokenization scheme in the original BERT.
            wordpiece = unkString;
            wordpieceToken = unkToken;
            break;
          }
          end -= 1;
        }

        if (wordpiece == null) {
          // Couldn't find any valid substring for the remaining characters in
          // the word. Emit UNK token and move on to the next word.
          isBad = true;
          break;
        }

        // Add current substring to subTokens
        wordpieces.add(wordpiece);
        wordTokens.add(wordpieceToken!);

        start = end;
      }

      // Add subtoken to outputTokens if the token was valid, otherwise add UNK
      if (isBad) {
        outputTokens.add(unkToken);
      } else {
        outputTokens.addAll(wordTokens);
      }

      if (outputTokens.length >= maxInputTokens - 1) {
        break;
      }
    }

    if (outputTokens.length >= maxInputTokens - 1) {
      outputTokens = outputTokens.sublist(0, maxInputTokens - 1);
    }
    outputTokens.add(endToken);

    return outputTokens;
  }


  List<int> tokenize(String text) {
    return _createSubstrings(text);
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
}
