import 'package:fonnx/tokenizers/tokenizer_bert_vocab.dart';
import 'package:fonnx/tokenizers/tokenizer_utils.dart';

class WordpieceTokenizer {
  final Map<String, int> vocab;
  final String unkToken;
  final int? startToken;
  final int? endToken;
  final int maxInputTokens;
  final int maxInputCharsPerWord;

  const WordpieceTokenizer({
    required this.vocab,
    required this.unkToken,
    required this.startToken,
    required this.endToken,
    required this.maxInputTokens,
    required this.maxInputCharsPerWord,
  });

  static const WordpieceTokenizer _cachedBertTokenizer = WordpieceTokenizer(
    vocab: vocabBert,
    unkToken: '[UNK]',
    startToken: 101,
    endToken: 102,
    maxInputTokens: 256,
    maxInputCharsPerWord: 100,
  );

  factory WordpieceTokenizer.bert() {
    return _cachedBertTokenizer;
  }

  List<String> _splitToStringTokens(String text) {
    List<String> outputTokens = [];
    List<String> tokens = whitespaceTokenize(text);

    for (var token in tokens) {
      List<String> chars = token.split('');
      if (chars.length > maxInputCharsPerWord) {
        outputTokens.add(unkToken);
        continue;
      }

      bool isBad = false;
      int start = 0;
      List<String> subTokens = [];
      while (start < chars.length) {
        int end = chars.length;
        String? curSubstr;
        while (start < end) {
          String substr = chars.sublist(start, end).join();
          if (start > 0) {
            substr = "##$substr";
          }
          final vocabIndex = vocab[substr];
          if (vocabIndex != null) {
            curSubstr = substr;
            break;
          }
          end -= 1;
        }

        if (curSubstr == null) {
          isBad = true;
          break;
        }
        subTokens.add(curSubstr);
        start = end;
      }

      if (isBad) {
        outputTokens.add(unkToken);
      } else {
        outputTokens.addAll(subTokens);
      }
      if (outputTokens.length >= maxInputTokens) {
        outputTokens = outputTokens.sublist(0, maxInputTokens - 1);
        break;
      }
    }

    return outputTokens;
  }

  List<int> tokenize(String text) {
    final strings = _splitToStringTokens(text);
    final hasEndToken = endToken != null;
    final hasStartToken = startToken != null;
    final tokens = <int>[if (hasStartToken) startToken!];

    final maxProducedTokenCount =
        maxInputTokens - (hasEndToken ? 1 : 0) - (hasStartToken ? 1 : 0);
    for (var string in strings) {
      if (!vocab.containsKey(string)) {
        continue;
      }
      tokens.add(vocab[string]!);
      if (tokens.length >= maxProducedTokenCount) {
        break;
      }
    }
    if (endToken != null) {
      tokens.add(endToken!);
    }
    return tokens;
  }
}
