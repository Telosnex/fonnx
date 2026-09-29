import 'package:fonnx/tokenizers/potion_base_8m_vocab.dart';
import 'package:fonnx/tokenizers/wordpiece_tokenizer.dart';
import 'package:ml_linalg/linalg.dart';

import 'minish_lab_abstract.dart'
    if (dart.library.io) 'minish_lab_native.dart'
    if (dart.library.js_interop) 'minish_lab_web.dart';

abstract class MinishLab {
  static MinishLab? _instance;
  String get modelPath;

  static MinishLab load(String path) {
    if (path.trim().isEmpty) throw ArgumentError.value(path, 'path');
    final current = _instance;
    if (current != null && current.modelPath != path) {
      throw StateError('MinishLab is already loaded from ${current.modelPath}');
    }
    _instance ??= getMinishLab(path);
    return _instance!;
  }

  /// Tokenizer for Potion Base 8M.
  ///
  /// For Potion 32M, explicitly import
  /// `package:fonnx/tokenizers/potion_32m_tokenizer.dart` and use its
  /// `potion32mTokenizer`. Keeping that vocabulary out of this library avoids
  /// loading it in debug builds of apps that only use 8M.
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
