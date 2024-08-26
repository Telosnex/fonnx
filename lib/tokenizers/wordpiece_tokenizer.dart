import 'package:diacritic/diacritic.dart';
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

  List<TextAndTokens> _createSubstrings(String text, {int? maxTokens}) {
    final max = maxTokens ?? maxInputTokens;
    text = text.trim();
    if (text.isEmpty) {
      return [
        TextAndTokens(text: '', tokens: [101, 102])
      ];
    }
    text = removeDiacritics(text);
    text = text.toLowerCase();

    List<List<int>> allOutputTokens = [];
    List<String> allOutputStrings = [];
    List<String> words = text.split(RegExp(r'\s+')); // Split on whitespace

    List<int> outputTokens = [startToken];
    List<String> outputString = [];
    for (final word in words) {
      if (word.length > maxInputCharsPerWord) {
        continue;
      }

      List<int> wordTokens = _tokenizeWord(word);
    
      if (outputTokens.length + wordTokens.length >= max - 1) {
        outputTokens.add(endToken);
        allOutputStrings.add(outputString.join(' '));
        allOutputTokens.add(outputTokens);
        outputString = [word];
        outputTokens = [startToken, ...wordTokens];
      } else {
        outputString.add(word);
        outputTokens.addAll(wordTokens);
      }
    }
    outputTokens.add(endToken);
    allOutputTokens.add(outputTokens);
    allOutputStrings.add(outputString.join(' '));
    assert(allOutputStrings.length == allOutputTokens.length);
    return List<TextAndTokens>.generate(allOutputStrings.length, (index) {
      return TextAndTokens(
        text: allOutputStrings[index],
        tokens: allOutputTokens[index],
      );
    });
  }

  List<int> _tokenizeWord(String word) {
    List<int> wordTokens = [];
    int start = 0;
    while (start < word.length) {
      int end = word.length;
      int? wordpieceToken;

      while (start < end) {
        String substr = word.substring(start, end);
        if (start > 0) {
          substr = "##$substr";
        }

        final token = encoder[substr];
        if (token != null) {
          wordpieceToken = token;
          break;
        }

        if (end - start == 1) {
          if (_isNoSpaceLanguageChar(word.codeUnitAt(start))) {
            wordpieceToken = unkToken;
            break;
          }
        }
        end--;
      }

      if (wordpieceToken == null) {
        return [unkToken];
      }

      wordTokens.add(wordpieceToken);
      start = end;
    }

    return wordTokens;
  }
  
  List<TextAndTokens> tokenize(String text, {int? maxTokens}) {
    return _createSubstrings(text, maxTokens: maxTokens);
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
