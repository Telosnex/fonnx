// Standard CTC prefix search over a lexicon trie. Independent implementation;
// no source from FUTO's GPL swipe library is used.
import 'dart:math' as math;
import 'dart:typed_data';

/// A spelling stored at a trie word node.
final class LexiconSurface {
  LexiconSurface(this.text, this.frequency);

  final String text;
  int frequency;
}

/// Trie node keyed by letter index (0 = `a`).
final class LexiconNode {
  LexiconNode(this.text, this.last);

  final children = <int, LexiconNode>{};

  /// Search-key prefix that this node represents.
  final String text;

  /// Letter index of the final character, or -1 for the root.
  final int last;

  /// Display spellings, in insertion order. Empty for non-word nodes.
  final surfaces = <LexiconSurface>[];

  /// Highest frequency among [surfaces].
  int frequency = 0;

  bool get isWord => surfaces.isNotEmpty;
}

/// Lowercase `a`-`z` search key, or null when [text] is not swipeable.
String? lexiconSearchKey(String text) {
  final key = text.toLowerCase().replaceAll(RegExp("['\u2019]"), '');
  return _searchKeyPattern.hasMatch(key) ? key : null;
}

final _searchKeyPattern = RegExp(r'^[a-z]+$');

/// Adds [surface] to [root]. Returns false when it is not swipeable.
bool addLexiconWord(LexiconNode root, String surface, int frequency) {
  final key = lexiconSearchKey(surface);
  if (key == null) return false;
  var node = root;
  for (final unit in key.codeUnits) {
    final parent = node;
    node = node.children.putIfAbsent(
      unit - 97,
      () => LexiconNode(parent.text + String.fromCharCode(unit), unit - 97),
    );
  }
  final existing = node.surfaces.where((s) => s.text == surface).firstOrNull;
  if (existing == null) {
    node.surfaces.add(LexiconSurface(surface, frequency));
  } else {
    existing.frequency = math.max(existing.frequency, frequency);
  }
  node.frequency = math.max(node.frequency, frequency);
  return true;
}

/// Blank-ending and letter-ending log probability of one prefix.
final class PrefixMass {
  double blank = double.negativeInfinity;
  double letter = double.negativeInfinity;
  double priority = double.negativeInfinity;

  double get total => logAdd(blank, letter);
}

double logAdd(double a, double b) {
  if (a == double.negativeInfinity) return b;
  if (b == double.negativeInfinity) return a;
  final hi = math.max(a, b), lo = math.min(a, b);
  return hi + math.log(1 + math.exp(lo - hi));
}

/// Trie-constrained CTC prefix search with length-normalized pruning.
///
/// [logits] is `[steps, classes]` row-major; the last class is blank. Each
/// prefix keeps separate blank- and letter-ending mass. Repeating the final
/// letter extends the prefix only from blank-ending mass. Beams are pruned by
/// `total / max(1, length)^gamma + beta * length`.
Map<LexiconNode, PrefixMass> ctcPrefixSearch(
  Float32List logits,
  int steps,
  int classes,
  LexiconNode root, {
  required int beam,
  double gamma = 0,
  double beta = 0,
}) {
  var states = {root: PrefixMass()..blank = 0};
  final blank = classes - 1;
  final divisors = List<double>.generate(
    steps + 1,
    (i) => math.pow(math.max(1, i), gamma).toDouble(),
  );
  for (var t = 0; t < steps; t++) {
    final next = <LexiconNode, PrefixMass>{};
    final base = t * classes;
    for (final entry in states.entries) {
      final node = entry.key, old = entry.value;
      final same = next.putIfAbsent(node, PrefixMass.new);
      same.blank = logAdd(same.blank, old.total + logits[base + blank]);
      if (node.last >= 0) {
        same.letter = logAdd(
          same.letter,
          old.letter + logits[base + node.last],
        );
      }
      for (final edge in node.children.entries) {
        final destination = next.putIfAbsent(edge.value, PrefixMass.new);
        final previous = edge.key == node.last ? old.blank : old.total;
        destination.letter = logAdd(
          destination.letter,
          previous + logits[base + edge.key],
        );
      }
    }
    final ordered = next.entries.toList();
    for (final entry in ordered) {
      final length = entry.key.text.length;
      entry.value.priority =
          entry.value.total / divisors[math.min(length, steps)] + beta * length;
    }
    ordered.sort((a, b) => b.value.priority.compareTo(a.value.priority));
    states = Map.fromEntries(ordered.take(beam));
  }
  return states;
}
