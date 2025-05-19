import 'package:fonnx/tokenizers/potion_32m_vocab.dart';
import 'package:fonnx/tokenizers/potion_base_8m_vocab.dart';
import 'package:fonnx/tokenizers/wordpiece_tokenizer.dart';
import 'package:ml_linalg/linalg.dart';

import 'minish_lab_abstract.dart'
    if (dart.library.io) 'minish_lab_native.dart'
    if (dart.library.js_interop) 'minish_lab_web.dart';

abstract class MinishLab {
  static MinishLab? _instance;

  static MinishLab load(String path) {
    _instance ??= getMinishLab(path);
    return _instance!;
  }

// See [minishLabEncoder] and [minishLabDecoder] in minish_lab_vocab.dart
// for the vocabulary used in this tokenizer.
//
// Derived special tokens using:
// When encoding text for BERT models:
// 1.  [CLS] is added at the beginning of the sequence
// 2.  [SEP] is added at the end of the sequence
// 3.  For sentence pair tasks, [SEP] is also used between the two sentences
//  Other special tokens in the configuration:
// •  [PAD] (token ID: 0): Used for padding sequences to a fixed length
// •  [UNK] (token ID: 1): Used for unknown tokens not in the vocabulary
// •  [MASK] (token ID: 4): Used for masked language modeling tasks
  static final potion32mTokenizer = WordpieceTokenizer(
    encoder: potion32mEncoder,
    decoder: minishLabDecoder,
    unkString: '[UNK]',
    unkToken: 1,
    startToken: 2,
    endToken: 3,
    maxInputTokens: 256,
    maxInputCharsPerWord: 100,
  );

  static final potion8mTokenizer = WordpieceTokenizer(
    encoder: potionBase8mEncoder,
    decoder: potionBase8mDecoder,
    unkString: '[UNK]',
    unkToken: 1,
    startToken: 2,
    endToken: 3,
    maxInputTokens: 256,
    maxInputCharsPerWord: 100,
  );

  Future<Vector> getEmbeddingAsVector(List<int> tokens);
}
