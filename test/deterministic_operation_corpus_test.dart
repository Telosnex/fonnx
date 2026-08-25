import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fonnx/models/keyword_spotter/keyword_spotter.dart';
import 'package:fonnx/models/keyword_spotter/src/streaming_fbank.dart';
import 'package:fonnx/models/magika/magika.dart';
import 'package:fonnx/models/pyannote/pyannote.dart';
import 'package:fonnx/models/whisper/whisper.dart';

const deterministicOperationCorpusVersion = 1;
const deterministicOperationIds = <String>[
  'v1/fbank-chunk-1',
  'v1/fbank-chunk-7',
  'v1/fbank-chunk-159',
  'v1/fbank-chunk-160',
  'v1/fbank-chunk-161',
  'v1/fbank-chunk-257',
  'v1/fbank-chunk-731',
  'v1/fbank-chunk-997',
  'v1/magika-size-0',
  'v1/magika-size-1',
  'v1/magika-size-511',
  'v1/magika-size-512',
  'v1/magika-size-513',
  'v1/magika-size-1025',
  'v1/magika-size-1536',
  'v1/magika-size-1537',
  'v1/pcm16-extremes',
  'v1/whisper-timestamps-leading',
  'v1/whisper-timestamps-multiple',
  'v1/keyword-config-snapshot',
  'v1/keyword-config-hostile-values',
];

void main() {
  test('v1 operation manifest is stable and unique', () {
    expect(deterministicOperationCorpusVersion, 1);
    expect(deterministicOperationIds, hasLength(21));
    expect(deterministicOperationIds.toSet(), hasLength(21));
    expect(deterministicOperationIds, everyElement(startsWith('v1/')));
  });

  test('streaming fbank is invariant to prime and boundary chunk sizes', () {
    final source = Float32List(8191);
    for (var index = 0; index < source.length; index++) {
      source[index] =
          0.31 * math.sin(2 * math.pi * 437 * index / 16000) +
          0.07 * math.sin(2 * math.pi * 1193 * index / 16000) +
          (index % 997 == 0 ? 0.4 : 0);
    }
    final baseline = StreamingKwsFbank()
      ..accept(source)
      ..finish();
    final expected = baseline.getFrames(0, baseline.numFramesReady);

    for (final chunkSize in const [1, 7, 159, 160, 161, 257, 731, 997]) {
      final actual = StreamingKwsFbank();
      for (var offset = 0; offset < source.length; offset += chunkSize) {
        final end = math.min(offset + chunkSize, source.length);
        actual.accept(Float32List.fromList(source.sublist(offset, end)));
      }
      actual.finish();
      expect(
        actual.numFramesReady,
        baseline.numFramesReady,
        reason: 'chunk=$chunkSize',
      );
      expect(
        actual.getFrames(0, actual.numFramesReady),
        expected,
        reason: 'chunk=$chunkSize',
      );
    }
  });

  test('Magika extraction matches an independent boundary oracle', () {
    for (final length in const [0, 1, 511, 512, 513, 1025, 1536, 1537]) {
      final content = Uint8List.fromList(
        List<int>.generate(length, (index) => (index * 73 + 19) & 0xff),
      );
      final actual = extractFeaturesFromBytes(content).all;
      final expected = _referenceMagikaFeatures(content);
      expect(actual, expected, reason: 'length=$length');
      expect(actual, hasLength(1536), reason: 'length=$length');
    }
  });

  test('PCM16 conversion preserves signed extrema and zero', () {
    final bytes = Uint8List.fromList(const [
      0x00,
      0x80,
      0xff,
      0xff,
      0x00,
      0x00,
      0xff,
      0x7f,
    ]);
    expect(
      Pyannote.int16PcmBytesToFloat32(bytes),
      Float32List.fromList(const [-1, -1 / 32768, 0, 32767 / 32768]),
    );
  });

  test('Whisper timestamp cleanup handles leading and repeated markers', () {
    expect(Whisper.removeTimestamps('<|0.00|> rain in Spain'), 'rain in Spain');
    expect(
      Whisper.removeTimestamps('<|0.00|>rain<|1.00|> in <|2.00|>Spain'),
      'rain in Spain',
    );
  });

  test('keyword configuration is validated and deeply snapshotted', () {
    final spokenForms = <String>['tell us next'];
    final tokenIds = <int>[410, 142, 446];
    final input = <KeywordPhrase>[
      KeywordPhrase(
        'telosnex',
        spokenForms: spokenForms,
        spokenTokenSequences: [
          KeywordTokenSequence(
            tokenizerId: KeywordSpotter.tokenizerId,
            tokenIds: tokenIds,
          ),
        ],
      ),
    ];
    final snapshot = validatedKeywordPhraseSnapshot(input);
    input.clear();
    spokenForms[0] = 'mutated';
    tokenIds[0] = 999;
    expect(snapshot.single.text, 'telosnex');
    expect(snapshot.single.spokenForms, const ['tell us next']);
    expect(snapshot.single.spokenTokenSequences.single.tokenIds, [
      410,
      142,
      446,
    ]);
    expect(
      () => snapshot.add(const KeywordPhrase('x')),
      throwsUnsupportedError,
    );
    expect(() => snapshot.single.spokenForms.add('x'), throwsUnsupportedError);
    expect(
      () => snapshot.single.spokenTokenSequences.add(
        const KeywordTokenSequence(
          tokenizerId: KeywordSpotter.tokenizerId,
          tokenIds: [3],
        ),
      ),
      throwsUnsupportedError,
    );
    expect(
      () => snapshot.single.spokenTokenSequences.single.tokenIds.add(3),
      throwsUnsupportedError,
    );
  });

  test('keyword configuration rejects hostile numeric values', () {
    for (final phrase in const [
      KeywordPhrase('x', score: 0),
      KeywordPhrase('x', score: double.nan),
      KeywordPhrase('x', score: double.infinity),
      KeywordPhrase('x', threshold: 0),
      KeywordPhrase('x', threshold: double.nan),
      KeywordPhrase('x', threshold: double.infinity),
      KeywordPhrase('x', threshold: 1.01),
      KeywordPhrase('   '),
    ]) {
      expect(
        () => validatedKeywordPhraseSnapshot([phrase]),
        throwsArgumentError,
      );
    }
    expect(() => validatedKeywordPhraseSnapshot(const []), throwsArgumentError);
    expect(
      () => validatedKeywordPhraseSnapshot(const [
        KeywordPhrase(
          'x',
          spokenTokenSequences: [
            KeywordTokenSequence(
              tokenizerId: 'different-vocabulary',
              tokenIds: [3],
            ),
          ],
        ),
      ]),
      throwsArgumentError,
    );
    expect(
      () => validatedKeywordPhraseSnapshot(const [
        KeywordPhrase(
          'x',
          spokenTokenSequences: [
            KeywordTokenSequence(
              tokenizerId: KeywordSpotter.tokenizerId,
              tokenIds: [],
            ),
          ],
        ),
      ]),
      throwsArgumentError,
    );
  });
}

List<int> _referenceMagikaFeatures(Uint8List original) {
  const width = 512;
  const padding = 256;
  var first = 0;
  var last = original.length;
  while (first < last && const {10, 13, 32}.contains(original[first])) {
    first++;
  }
  while (last > first && const {10, 13, 32}.contains(original[last - 1])) {
    last--;
  }
  final bytes = original.sublist(first, last);

  List<int> left() => bytes.length >= width
      ? bytes.sublist(0, width)
      : <int>[...bytes, ...List<int>.filled(width - bytes.length, padding)];
  List<int> right() => bytes.length >= width
      ? bytes.sublist(bytes.length - width)
      : <int>[...List<int>.filled(width - bytes.length, padding), ...bytes];
  List<int> middle() {
    if (bytes.length >= width) {
      final start = bytes.length ~/ 2 - width ~/ 2;
      return bytes.sublist(start, start + width);
    }
    final missing = width - bytes.length;
    final leftPadding = missing ~/ 2;
    return <int>[
      ...List<int>.filled(leftPadding, padding),
      ...bytes,
      ...List<int>.filled(missing - leftPadding, padding),
    ];
  }

  return <int>[...left(), ...middle(), ...right()];
}
