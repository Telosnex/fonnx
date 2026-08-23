import 'package:fonnx/tokenizers/bert_vocab.dart';
import 'package:fonnx/tokenizers/wordpiece_tokenizer.dart';
import 'package:ml_linalg/linalg.dart';

import 'msmarco_mini_lm_l6_v3_abstract.dart'
    if (dart.library.io) 'msmarco_mini_lm_l6_v3_native.dart'
    if (dart.library.js_interop) 'msmarco_mini_lm_l6_v3_web.dart';

abstract class MsmarcoMiniLmL6V3 {
  static MsmarcoMiniLmL6V3? _instance;
  String get modelPath;

  static MsmarcoMiniLmL6V3 load(String path) {
    if (path.trim().isEmpty) throw ArgumentError.value(path, 'path');
    final current = _instance;
    if (current != null && current.modelPath != path) {
      throw StateError(
        'MsmarcoMiniLmL6V3 is already loaded from ${current.modelPath}',
      );
    }
    _instance ??= getMsmarcoMiniLmL6V3(path);
    return _instance!;
  }

  static final tokenizer = WordpieceTokenizer(
    encoder: bertEncoder,
    decoder: bertDecoder,
    unkString: '[UNK]',
    unkToken: 100,
    startToken: 101,
    endToken: 102,
    maxInputTokens: 512,
    maxInputCharsPerWord: 100,
  );

  Future<Vector> getEmbeddingAsVector(List<int> tokens);
}
