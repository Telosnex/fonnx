import 'package:diacritic/diacritic.dart';
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

  /// Checks if the given code unit represents a word and the tokenizer should
  /// treat it as such.
  ///
  /// For example, Chinese and Japanese words are not separated by spaces.
  bool _isNoSpaceLanguageChar(int codeUnit) {
    // Comment and implementation imitate https://github.com/huggingface/tokenizers/blob/0d8c57da48319a91fe9cd3e31a36b9bd29a8292c/tokenizers/src/normalizers/bert.rs#L36
    //
    // There is an error in the comment and thus the implementation: Japanese
    // Hiragana and Katakana are _not_ always used to write space-separated
    // words. In fact, I cannot find evidence that they are ever used to write
    // space-separated words.
    //
    // Therefore, this implementation is slightly different from the original.
    // It checks Hiragana in the Unicode block from U+3040 to U+309F.
    // It checks Katakana in the Unicode block from U+30A0 to U+30FF.
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

  (List<String>, List<List<int>>) _createSubstrings(String text) {
    text = text.trim();
    if (text.isEmpty) {
      return ([], []);
    }

    List<List<int>> allOutputTokens = [];
    List<String> allOutputStrings = [];
    List<String> words = text.split(RegExp(r'\s+')); // Split on whitespace

    List<int> outputTokens = [startToken];
    List<String> outputString = [];
    for (final word in words) {
      // Convert to lowercase individual characters. Why lowercase? The BERT
      // vocabulary doesn't have tokens with uppercase English letters.
      List<String> characters = word.toLowerCase().split('');

      if (characters.length > maxInputCharsPerWord) {
        continue;
      }

      bool wordUnknown = false;
      int start = 0;

      List<int> wordTokens = [];
      wordProcess:
      while (start < characters.length) {
        int end = characters.length;
        String? wordpiece;
        int? wordpieceToken;

        wordpieceProcess:
        while (start < end) {
          // Ensure e.g. Spanish/French/German don't end up with [UNK] tokens
          // for every word with a diacritic.
          var substr = characters.sublist(start, end).join();
          final originalSubstr = substr;
          substr = removeDiacritics(substr);
          // Append "##" in front of the substring if it's not at the start of
          // the token
          if (start > 0) {
            substr = "##$substr";
          }

          // Check if the substring exists in the vocabulary
          final token = encoder[substr];
          if (token != null) {
            wordpiece = originalSubstr;
            wordpieceToken = token;
            break wordpieceProcess;
          } else if (end - start == 1) {
            if (_isNoSpaceLanguageChar(characters[start].codeUnitAt(0))) {
              // Chinese character without token? add UNK token. Essentially,
              // we are treating each Chinese character as a word. This matches
              // the character-based tokenization scheme in the original BERT.
              wordpiece = unkString;
              wordpieceToken = unkToken;
              break wordpieceProcess;
            }
          }
          end -= 1;
        }

        if (wordpiece == null) {
          // Couldn't find any valid substring for the remaining characters in
          // the word. Emit UNK token and move on to the next word.
          wordUnknown = true;
          break wordProcess;
        }

        // Add current substring to subTokens
        wordTokens.add(wordpieceToken!);
        start = end;
      }

      final stringForWord = wordUnknown ? unkString : word;
      final tokensForWord = wordUnknown ? [unkToken] : wordTokens;
      if (outputTokens.length + tokensForWord.length >= maxInputTokens - 1) {
        outputTokens.add(endToken);
        allOutputStrings.add(outputString.join(' '));
        allOutputTokens.add(outputTokens);
        // This does not account for the event that tokensForWord is longer than
        // maxInputTokens - 1. In that case, we would need to split
        // tokensForWord. This is very unlikely to happen, due to
        // maxInputCharsPerWord being << maxInputTokens. It is also irrelevant
        // because the model will simply truncate the input to maxInputTokens.
        outputString = [stringForWord];
        outputTokens = [startToken, ...tokensForWord];
      } else {
        outputString.add(stringForWord);
        outputTokens.addAll(tokensForWord);
      }
    }
    outputTokens.add(endToken);
    allOutputTokens.add(outputTokens);
    allOutputStrings.add(outputString.join(' '));
    return (allOutputStrings, allOutputTokens);
  }

  List<List<int>> tokenize(String text) {
    final answer = _createSubstrings(text);
    final tokens = answer.$2;
    return tokens;
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
