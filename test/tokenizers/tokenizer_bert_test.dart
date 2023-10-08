import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fonnx/tokenizers/wordpiece_tokenizer.dart';

void main() {
  test('Generate vocab', skip: 'only needed for bootstrapping', () async {
    String vocabPath = 'test/tokenizers/bert-base-uncased-vocab.txt';
    File file = File(vocabPath);
    final string = await file.readAsString();
    final stringToTokenIndex = <String, int>{};
    for (final (index, line) in string.split('\n').indexed) {
      final string = line.trimRight();
      if (string.isEmpty) {
        debugPrint('WARNING: vocab has empty string');
        continue;
      }
      if (stringToTokenIndex.containsKey(string)) {
        debugPrint('WARNING: vocab has seemingly duplicate string `$string`');
        continue;
      }
      stringToTokenIndex[string] = index;
    }

    final sb = StringBuffer();
    sb.writeln('const Map<String, int> vocabBert = {');
    for (var string in stringToTokenIndex.keys) {
      final tokenIndex = stringToTokenIndex[string];
      // Its complicated enough that it can't be auto-fixed and I do not watch
      // to touch it right now. :^)
      // ignore: prefer_interpolation_to_compose_strings
      final separator = string.contains('"') ? "'''" : '"""';
      sb.writeln("  r$separator$string$separator: $tokenIndex,");
    }
    sb.writeln('};');

    const outputPath = 'test/outputs/tokenizer_bert_vocab.dart';
    final outputFile = File(outputPath);
    await outputFile.writeAsString(sb.toString());
  });

  test('hello world tokens', () async {
    final tokenizer = WordpieceTokenizer.bert();

    final tokens = tokenizer.tokenize('hello world bataclan');
    expect(tokens, equals([101, 7592, 2088, 7151, 6305, 5802, 102]));
  });

  test('extended string', () async {
    final tokenizer = WordpieceTokenizer.bert();

    final tokens = tokenizer.tokenize(
        'the dogs caused much consternation the rain in spain falls mainly on the plain');
    expect(
      tokens,
      equals([
        101,
        1996,
        6077,
        3303,
        2172,
        9530,
        6238,
        9323,
        1996,
        4542,
        1999,
        3577,
        4212,
        3701,
        2006,
        1996,
        5810,
        102,
      ],)
    );
  });
}
