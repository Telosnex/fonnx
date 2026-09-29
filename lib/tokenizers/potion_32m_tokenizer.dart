import 'package:fonnx/tokenizers/potion_32m_vocab.dart';
import 'package:fonnx/tokenizers/wordpiece_tokenizer.dart';

/// Tokenizer for Potion Retrieval 32M.
///
/// Import this library only when using the 32M model. The tokenizer was formerly
/// available as `MinishLab.potion32mTokenizer`; a separate library keeps its
/// large vocabulary out of the import graph of 8M-only applications.
final potion32mTokenizer = WordpieceTokenizer(
  encoder: potion32mEncoder,
  decoder: minishLabDecoder,
  unkString: '[UNK]',
  unkToken: 1,
  startToken: 2,
  endToken: 3,
  maxInputTokens: 256,
  maxInputCharsPerWord: 100,
);
