import 'package:ml_linalg/linalg.dart';

/// A class that represents a text and its corresponding tokens.
///
/// Note that equality is only based on the text, not the tokens.
/// Two [TextAndTokens] objects could compare as equal even if the tokens
/// are from different tokenizers.
///
/// This is chosen to avoid expensive deep equals checks.
class TextAndTokens {
  final String text;
  final List<int> tokens;

  TextAndTokens({required this.text, required this.tokens});

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    // Avoid expensive deep equals check by only comparing text.
    return other is TextAndTokens && other.text == text;
  }

  @override
  int get hashCode => text.hashCode;
}

/// A class that represents a text and its corresponding embedding.
///
/// Note that equality is only based on the text, not the embedding.
/// Two [TextAndVector] objects could compare as equal even if the embeddings
/// are from different models.
///
/// This is chosen to avoid expensive deep equals checks.
class TextAndVector {
  final String text;
  final Vector embedding;

  TextAndVector({required this.text, required this.embedding});
}
