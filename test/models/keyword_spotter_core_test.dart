import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fonnx/models/keyword_spotter/keyword_spotter.dart';
import 'package:fonnx/models/keyword_spotter/src/context_graph.dart';
import 'package:fonnx/models/keyword_spotter/src/english_tokenizer.dart';
import 'package:fonnx/models/keyword_spotter/src/streaming_fbank.dart';

void main() {
  group('EnglishKwsTokenizer', () {
    final tokenizer = EnglishKwsTokenizer();

    test('matches SentencePiece unigram reference', () {
      expect(tokenizer.encode('rain in Spain'), [215, 46, 16, 219, 354]);
      expect(tokenizer.encode('mainly on the plain'), [
        110,
        46,
        51,
        64,
        5,
        76,
        118,
        46,
      ]);
      expect(tokenizer.encode('hey telosnex'), [
        49,
        17,
        62,
        10,
        120,
        3,
        102,
        193,
      ]);
      expect(tokenizer.encode("don't-stop"), [186, 13, 4, 115, 3, 4, 22, 26]);
      expect(tokenizer.encode('tell us next'), [410, 142, 446]);
      expect(tokenizer.encode('tell us nucks'), [410, 142, 20, 9, 28, 122, 3]);
      expect(tokenizer.encode('tell low snacks'), [
        410,
        218,
        56,
        31,
        9,
        25,
        122,
        3,
      ]);
      expect(tokenizer.encode('tell us necks'), [410, 142, 304, 122, 3]);
    });

    test('normalizes English whitespace and case', () {
      expect(
        tokenizer.encode('  RAIN\tIN   spain '),
        tokenizer.encode('rain in Spain'),
      );
    });

    test('rejects unsupported language and punctuation', () {
      expect(() => tokenizer.encode('hé computer'), throwsArgumentError);
      expect(() => tokenizer.encode('hey, computer'), throwsArgumentError);
      expect(() => tokenizer.encode('   '), throwsArgumentError);
    });
  });

  group('ContextGraph', () {
    test('supports overlapping phrases and failure links', () {
      final graph = ContextGraph(
        const [
          [1, 2],
          [2, 3],
        ],
        const [KeywordPhrase('one two'), KeywordPhrase('two three')],
      );
      var state = graph.root;
      state = graph.forward(state, 1).state;
      final firstMatch = graph.forward(state, 2);
      expect(firstMatch.matchedState?.phrase, 'one two');
      final overlap = graph.forward(firstMatch.state, 3);
      expect(overlap.matchedState?.phrase, 'two three');
    });

    test('returns to root and removes boost for unrelated tokens', () {
      final graph = ContextGraph(
        const [
          [10, 11],
        ],
        const [KeywordPhrase('test')],
      );
      final partial = graph.forward(graph.root, 10);
      final failed = graph.forward(partial.state, 99);
      expect(failed.state, same(graph.root));
      expect(failed.score, -1);
    });
  });

  test('streaming fbank matches kaldi-native-fbank reference', () async {
    final samples = Float32List(1600);
    for (var i = 0; i < samples.length; i++) {
      samples[i] =
          0.3 * math.sin(2 * math.pi * 440 * i / 16000) +
          0.1 * math.sin(2 * math.pi * 1200 * i / 16000);
    }
    final fbank = StreamingKwsFbank();
    // Deliberately split at a non-frame boundary to exercise streaming state.
    fbank.accept(Float32List.fromList(samples.sublist(0, 731)));
    fbank.accept(Float32List.fromList(samples.sublist(731)));

    final expected =
        (await File('test/data/kws_fbank_golden.csv').readAsLines())
            .map(
              (line) =>
                  line.split(',').map(double.parse).toList(growable: false),
            )
            .toList(growable: false);
    final actual = fbank.getFrames(0, 3);
    for (var frame = 0; frame < 3; frame++) {
      for (var bin = 0; bin < 80; bin++) {
        expect(
          actual[frame * 80 + bin],
          closeTo(expected[frame][bin], 1e-3),
          reason: 'frame $frame, mel bin $bin',
        );
      }
    }
  });

  test('streaming fbank stays aligned across a real utterance', () async {
    final bytes = await File(
      'test/data/audio_sample_ac1_ar16000.pcm',
    ).readAsBytes();
    final pcm = ByteData.sublistView(bytes);
    final samples = Float32List(bytes.length ~/ 2);
    for (var index = 0; index < samples.length; index++) {
      samples[index] = pcm.getInt16(index * 2, Endian.little) / 32768;
    }

    final fbank = StreamingKwsFbank()..accept(Float32List(10240));
    const chunkSizes = [1, 159, 731, 1600, 997, 320];
    var offset = 0;
    var chunk = 0;
    while (offset < samples.length) {
      final requested = chunkSizes[chunk++ % chunkSizes.length];
      final end = math.min(offset + requested, samples.length);
      fbank.accept(Float32List.fromList(samples.sublist(offset, end)));
      offset = end;
    }
    fbank
      ..accept(Float32List(8000))
      ..finish();

    expect(fbank.numFramesReady, 609);
    final rows = await File(
      'test/data/kws_fbank_streaming_golden.csv',
    ).readAsLines();
    for (final row in rows) {
      final columns = row.split(',');
      final frame = int.parse(columns.first);
      final expected = columns.skip(1).map(double.parse).toList();
      final actual = fbank.getFrames(frame, 1);
      for (var bin = 0; bin < StreamingKwsFbank.featureDimension; bin++) {
        expect(
          actual[bin],
          closeTo(expected[bin], 1e-3),
          reason: 'frame $frame, mel bin $bin',
        );
      }
    }
  });
}
