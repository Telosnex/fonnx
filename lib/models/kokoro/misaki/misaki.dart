/// English text -> Kokoro phonemes: spaCy tokenizer/tagger + misaki G2P.
library;

import 'dart:typed_data';

import 'package:fonnx/models/kokoro/misaki/misaki_en.dart';
import 'package:fonnx/models/kokoro/misaki/spacy_en.dart';

export 'package:fonnx/models/kokoro/misaki/misaki_en.dart'
    show MisakiFallback, MisakiG2P, MisakiLexicon, MToken;

class Misaki {
  Misaki({required this.spacy, required this.g2p});

  /// Builds from the asset contents: misaki's `us_gold.json` and
  /// `us_silver.json` (decoded), and spaCy's exported config and weights.
  factory Misaki.load({
    required Map<String, dynamic> gold,
    required Map<String, dynamic> silver,
    required String spacyConfigJson,
    required Uint8List spacyWeights,
    String unk = '❓',
    bool british = false,
    MisakiFallback? fallback,
  }) => Misaki(
    spacy: SpacyEnglish.load(spacyConfigJson, spacyWeights),
    g2p: MisakiG2P(
      lexicon: MisakiLexicon(gold: gold, silver: silver, british: british),
      unk: unk,
      fallback: fallback,
    ),
  );

  final SpacyEnglish spacy;
  final MisakiG2P g2p;

  /// Converts [text] to a phoneme string, like misaki's `G2P.__call__`.
  String phonemize(String text) => phonemizeWithTokens(text).$1;

  (String, List<MToken>) phonemizeWithTokens(String text) {
    final pre = MisakiG2P.preprocess(text);
    final doc = spacy(pre.text);
    final tokens = [
      for (final t in doc)
        MToken(text: t.text, tag: t.tag, whitespace: t.whitespace),
    ];
    MisakiG2P.applyFeatures(
      tokens,
      [for (final t in doc) t.idx],
      pre.text,
      pre.tokens,
      pre.features,
    );
    return g2p.phonemizeTokens(tokens);
  }
}
