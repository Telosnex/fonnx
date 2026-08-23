import 'package:fonnx/tokenizers/bert_vocab.dart';
import 'package:fonnx/tokenizers/wordpiece_tokenizer.dart';
import 'package:ml_linalg/linalg.dart';

import 'mini_lm_l6_v2_abstract.dart'
    if (dart.library.io) 'mini_lm_l6_v2_native.dart'
    if (dart.library.js_interop) 'mini_lm_l6_v2_web.dart';

abstract class MiniLmL6V2 {
  static MiniLmL6V2? _instance;
  String get modelPath;

  static MiniLmL6V2 load(String path) {
    if (path.trim().isEmpty) throw ArgumentError.value(path, 'path');
    final current = _instance;
    if (current != null && current.modelPath != path) {
      throw StateError('MiniLmL6V2 is already loaded from ${current.modelPath}');
    }
    _instance ??= getMiniLmL6V2(path);
    return _instance!;
  }

  static final tokenizer = WordpieceTokenizer(
    encoder: bertEncoder,
    decoder: bertDecoder,
    unkString: '[UNK]',
    unkToken: 100,
    startToken: 101,
    endToken: 102,
    maxInputTokens: 256,
    maxInputCharsPerWord: 100,
  );

  Future<Vector> getEmbeddingAsVector(List<int> tokens);
}
