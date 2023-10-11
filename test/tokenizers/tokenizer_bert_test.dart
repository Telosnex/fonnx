import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fonnx/tokenizers/wordpiece_tokenizer.dart';

void main() {
  group('tokenize', () {
    test('hello world tokens', () async {
      final tokenizer = WordpieceTokenizer.bert();

      final tokens = tokenizer.tokenize('hello world');
      expect(tokens, equals([101, 7592, 2088, 102]));
    });

    test('emoji', () async {
      final tokenizer = WordpieceTokenizer.bert();
      final tokens = tokenizer.tokenize('👍');
      expect(tokens, equals([101, 100, 102]));
    });

    test('text & emoji', () async {
      final tokenizer = WordpieceTokenizer.bert();
      final tokens = tokenizer.tokenize('That looks great 👍');
      expect(tokens, equals([101, 2008, 3504, 2307, 100, 102]));
    });

    test('chinese', () async {
      final tokenizer = WordpieceTokenizer.bert();
      // String from https://github.com/huggingface/tokenizers/blob/0d8c57da48319a91fe9cd3e31a36b9bd29a8292c/tokenizers/src/pre_tokenizers/bert.rs#L52
      final tokens = tokenizer.tokenize('野口里佳 Noguchi Rika');
      expect(
          tokens,
          equals(
              [101, 1963, 30314, 30488, 100, 2053, 16918, 15544, 2912, 102]));
    });

    test('extremely long text stays within model limit', () async {
      const lipsum = '''
Lorem ipsum dolor sit amet, id assum putant est, in vis aliquid molestiae. Diam scriptorem delicatissimi nec no, usu an possim sensibus, maluisset consectetuer vis te. Ex suas lobortis mei. Ei scripta copiosae duo, ridens definitionem duo eu, prima oportere in ius.

Te has impedit oporteat, per te eruditi consetetur, magna libris blandit ea per. Nec euripidis intellegat accommodare ad. Sea sint autem doctus an. Ipsum aliquip perpetua vim te. Mel facilisi quaestio te, vix in ignota impedit delicata, et impetus similique pri.

Sententiae adipiscing vim ei. Cum at accusamus similique. Eum no nulla labitur, id mei eros aliquip, sed cu putent maluisset. Vel et congue partem convenire.

Aliquam feugiat vel ex, vim et simul perfecto singulis, pri ad deseruisse adipiscing. Mea elitr rationibus ex, ad sadipscing persequeris eloquentiam eos. Expetendis quaerendum reformidans ad pri, cibo dissentias pro ne. Vis facer offendit pertinacia et, eu sit rebum appareat, te patrioque evertitur cum. Timeam prompta nam no. Ius ex atqui repudiare, justo mediocrem cum ad, nec utinam erroribus reformidans et.

Qui rebum delectus et, ad elit deserunt inimicus quo, vix ne molestie dissentias suscipiantur. Ei has oratio veniam nostro, pri at laudem impedit consulatu. Semper denique te usu, quando epicurei nam cu, ut eleifend temporibus sit. Impetus laoreet mentitum quo in.
''';
      final tokenizer = WordpieceTokenizer.bert();
      final tokens = tokenizer.tokenize(lipsum);
      expect(tokens.length, equals(256));
      final string = tokenizer.detokenize(tokens);
      // This ensures the input string did exceed the model's max input length.
      expect(string, isNot(equals(lipsum)));
    });

    test('sentence', () async {
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
            102
          ]));
    });
  });

  group('detokenize', () {
    test('hello world', () {
      final tokenizer = WordpieceTokenizer.bert();
      final string = tokenizer.detokenize([101, 7592, 2088, 102]);
      expect(string, equals('hello world'));
    });

    test('emoji', () async {
      final tokenizer = WordpieceTokenizer.bert();
      final string = tokenizer.detokenize([101, 100, 102]);
      expect(string, equals('[UNK]'));
    });

    test('text & emoji', () async {
      final tokenizer = WordpieceTokenizer.bert();
      final string = tokenizer.detokenize([101, 2008, 3504, 2307, 100, 102]);
      expect(string, equals('that looks great [UNK]'));
    });

    test('chinese', () async {
      final tokenizer = WordpieceTokenizer.bert();
      final tokens = tokenizer.detokenize(
          [101, 1963, 30314, 30488, 100, 2053, 16918, 15544, 2912, 102]);
      expect(tokens, equals('野口里 [UNK] noguchi rika'));
    });

    test('sentence', () async {
      final tokenizer = WordpieceTokenizer.bert();
      final string = tokenizer.detokenize([
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
        102
      ]);
      expect(
          string,
          equals(
              'the dogs caused much consternation the rain in spain falls mainly on the plain'));
    });
  });

  test('Generate coders', skip: 'coder generator', () async {
    String vocabPath = 'test/tokenizers/bert-base-uncased-vocab.txt';
    File file = File(vocabPath);
    final string = await file.readAsString();
    final strings = <String>[];
    final stringToTokenIndex = <String, int>{};
    for (final line in string.split('\n')) {
      final string = line.trimRight();
      if (string.isEmpty) {
        debugPrint('WARNING: vocab has empty string');
        continue;
      }
      if (stringToTokenIndex.containsKey(string)) {
        debugPrint('WARNING: vocab has seemingly duplicate string `$string`');
        continue;
      }
      strings.add(string);
    }

    final encoder = StringBuffer();
    final decoder = StringBuffer();
    encoder.writeln('const Map<String, int> bertEncoder = {');
    decoder.writeln('const List<String> bertDecoder = [');
    for (final (index, string) in strings.indexed) {
      // Its complicated enough that it can't be auto-fixed and I do not watch
      // to touch it right now. :^)
      // ignore: prefer_interpolation_to_compose_strings
      final separator = string.contains('"') ? "'''" : '"""';
      encoder.writeln("  r$separator$string$separator: $index,");
      decoder.writeln("  r$separator$string$separator,");
    }
    encoder.writeln('};');
    decoder.writeln('];');

    final encoderString = encoder.toString();
    final decoderString = decoder.toString();
    const outputPath = 'test/outputs/bert_vocab.dart';
    final outputFile = File(outputPath);
    await outputFile.writeAsString('$encoderString\n\n$decoderString');
  });
}
