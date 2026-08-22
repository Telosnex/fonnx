import '../keyword_spotter_types.dart';

final class ContextState {
  ContextState({
    required this.token,
    required this.tokenScore,
    required this.nodeScore,
    required this.outputScore,
    this.level = 0,
    this.acousticThreshold = 0,
    this.isEnd = false,
    this.phrase = '',
  });

  final int token;
  double tokenScore;
  double nodeScore;
  double outputScore;
  final int level;
  double acousticThreshold;
  bool isEnd;
  String phrase;
  final Map<int, ContextState> next = {};
  late ContextState fail;
  ContextState? output;
}

final class ContextStep {
  const ContextStep(this.score, this.state, this.matchedState);

  final double score;
  final ContextState state;
  final ContextState? matchedState;
}

final class ContextGraph {
  ContextGraph(List<List<int>> tokenIds, List<KeywordPhrase> phrases)
    : root = ContextState(
        token: -1,
        tokenScore: 0,
        nodeScore: 0,
        outputScore: 0,
      ) {
    if (tokenIds.isEmpty || tokenIds.length != phrases.length) {
      throw ArgumentError('At least one tokenized phrase is required');
    }
    root.fail = root;
    _build(tokenIds, phrases);
    _fillFailureAndOutputLinks();
  }

  final ContextState root;

  void _build(List<List<int>> tokenIds, List<KeywordPhrase> phrases) {
    for (var phraseIndex = 0; phraseIndex < tokenIds.length; phraseIndex++) {
      final ids = tokenIds[phraseIndex];
      final phrase = phrases[phraseIndex];
      if (ids.isEmpty) {
        throw ArgumentError.value(phrase.text, 'phrase', 'Has no tokens');
      }
      var node = root;
      for (var tokenIndex = 0; tokenIndex < ids.length; tokenIndex++) {
        final token = ids[tokenIndex];
        final isEnd = tokenIndex == ids.length - 1;
        final existing = node.next[token];
        if (existing == null) {
          final child = ContextState(
            token: token,
            tokenScore: phrase.score,
            nodeScore: node.nodeScore + phrase.score,
            outputScore: isEnd ? node.nodeScore + phrase.score : 0,
            level: tokenIndex + 1,
            acousticThreshold: isEnd ? phrase.threshold : 0,
            isEnd: isEnd,
            phrase: isEnd ? phrase.text : '',
          );
          node.next[token] = child;
          node = child;
        } else {
          existing.tokenScore = _max(phrase.score, existing.tokenScore);
          existing.nodeScore = node.nodeScore + existing.tokenScore;
          existing.isEnd = isEnd || existing.isEnd;
          existing.outputScore = existing.isEnd ? existing.nodeScore : 0;
          if (isEnd) {
            existing.phrase = phrase.text;
            existing.acousticThreshold = phrase.threshold;
          }
          node = existing;
        }
      }
    }
  }

  void _fillFailureAndOutputLinks() {
    final queue = <ContextState>[];
    for (final child in root.next.values) {
      child.fail = root;
      queue.add(child);
    }

    var queueIndex = 0;
    while (queueIndex < queue.length) {
      final current = queue[queueIndex++];
      for (final entry in current.next.entries) {
        var failure = current.fail;
        if (failure.next.containsKey(entry.key)) {
          failure = failure.next[entry.key]!;
        } else {
          failure = failure.fail;
          while (!failure.next.containsKey(entry.key)) {
            failure = failure.fail;
            if (failure.token == -1) {
              break;
            }
          }
          failure = failure.next[entry.key] ?? failure;
        }
        final child = entry.value;
        child.fail = failure;

        ContextState? output = failure;
        while (output != null && !output.isEnd) {
          output = output.fail;
          if (output.token == -1) {
            output = null;
          }
        }
        child.output = output;
        child.outputScore += output?.outputScore ?? 0;
        queue.add(child);
      }
    }
  }

  ContextStep forward(ContextState state, int token) {
    ContextState node;
    double score;
    final direct = state.next[token];
    if (direct != null) {
      node = direct;
      score = node.tokenScore;
    } else {
      node = state.fail;
      while (!node.next.containsKey(token)) {
        node = node.fail;
        if (node.token == -1) {
          break;
        }
      }
      node = node.next[token] ?? node;
      score = node.nodeScore - state.nodeScore;
    }
    final matched = node.isEnd ? node : node.output;
    return ContextStep(score + node.outputScore, node, matched);
  }

  ContextState? matched(ContextState state) {
    if (state.isEnd) {
      return state;
    }
    return state.output;
  }
}

double _max(double left, double right) => left > right ? left : right;
