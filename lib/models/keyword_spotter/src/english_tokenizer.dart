import 'english_vocabulary.dart';

/// Model-specific English unigram tokenizer.
///
/// This intentionally supports only the characters represented by the
/// GigaSpeech KWS model: A-Z, apostrophe, hyphen, and ASCII whitespace.
final class EnglishKwsTokenizer {
  EnglishKwsTokenizer() : _piecesByFirstCodeUnit = _indexPieces();

  final Map<int, List<int>> _piecesByFirstCodeUnit;

  static Map<int, List<int>> _indexPieces() {
    final result = <int, List<int>>{};
    // IDs 0-2 are <blk>, <sos/eos>, and <unk>, not normal pieces.
    for (var id = 3; id < englishKwsPieces.length; id++) {
      final piece = englishKwsPieces[id];
      result.putIfAbsent(piece.codeUnitAt(0), () => <int>[]).add(id);
    }
    return result;
  }

  List<int> encode(String phrase) {
    final normalized = normalize(phrase);
    final bestScore = List<double>.filled(
      normalized.length + 1,
      double.negativeInfinity,
    );
    final previousPosition = List<int>.filled(normalized.length + 1, -1);
    final previousPiece = List<int>.filled(normalized.length + 1, -1);
    bestScore[0] = 0;

    for (var position = 0; position < normalized.length; position++) {
      if (!bestScore[position].isFinite) {
        continue;
      }
      final candidates =
          _piecesByFirstCodeUnit[normalized.codeUnitAt(position)] ?? const [];
      for (final id in candidates) {
        final piece = englishKwsPieces[id];
        if (!normalized.startsWith(piece, position)) {
          continue;
        }
        final end = position + piece.length;
        final score = bestScore[position] + englishKwsPieceScores[id];
        if (score > bestScore[end]) {
          bestScore[end] = score;
          previousPosition[end] = position;
          previousPiece[end] = id;
        }
      }
    }

    if (previousPiece.last == -1) {
      throw ArgumentError.value(
        phrase,
        'phrase',
        'The English KWS vocabulary cannot represent this phrase',
      );
    }

    final reversed = <int>[];
    var position = normalized.length;
    while (position > 0) {
      reversed.add(previousPiece[position]);
      position = previousPosition[position];
    }
    return reversed.reversed.toList(growable: false);
  }

  String decode(Iterable<int> tokenIds) {
    final pieces = StringBuffer();
    for (final tokenId in tokenIds) {
      if (tokenId < 3 || tokenId >= englishKwsPieces.length) {
        throw ArgumentError.value(
          tokenId,
          'tokenIds',
          'Must contain only normal English KWS vocabulary token IDs',
        );
      }
      pieces.write(englishKwsPieces[tokenId]);
    }
    return pieces.toString().replaceAll('▁', ' ').trim().toLowerCase();
  }

  String normalize(String phrase) {
    final trimmed = phrase.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(phrase, 'phrase', 'Must not be empty');
    }
    final words = trimmed.split(RegExp(r'\s+'));
    final upper = words.join(' ').toUpperCase();
    if (!RegExp(r"^[A-Z'-]+(?: [A-Z'-]+)*$").hasMatch(upper)) {
      throw ArgumentError.value(
        phrase,
        'phrase',
        "English wake phrases support only A-Z, apostrophe, hyphen, and whitespace",
      );
    }
    return '▁${upper.replaceAll(' ', '▁')}';
  }

  String piece(int tokenId) => englishKwsPieces[tokenId];
}
