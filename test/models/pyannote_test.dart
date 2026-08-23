import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fonnx/models/pyannote/pyannote.dart';
import 'package:fonnx/models/pyannote/pyannote_native.dart';

void main() {
  const modelPath = 'example/assets/models/pyannote/pyannote_seg3.onnx';
  final pyannote = PyannoteNative(modelPath);

  void expectValidSegments(
    List<Map<String, dynamic>> segments, {
    required int speakerCount,
    required double audioDuration,
  }) {
    expect(segments, isNotEmpty);
    for (final segment in segments) {
      expect(segment.keys, containsAll(<String>['speaker', 'start', 'stop']));
      expect(segment['speaker'], isA<int>());
      expect(segment['speaker'] as int, inInclusiveRange(0, 2));
      expect(segment['start'], isA<double>());
      expect(segment['stop'], isA<double>());
      final start = segment['start'] as double;
      final stop = segment['stop'] as double;
      expect(start, isNonNegative);
      expect(stop, greaterThan(start));
      expect(stop, lessThanOrEqualTo(audioDuration));
    }
    expect(
      segments.map((segment) => segment['speaker']).toSet(),
      hasLength(speakerCount),
    );
  }

  Future<void> expectMatchesGolden(
    String goldenPath, {
    required int speakerCount,
  }) async {
    final golden =
        jsonDecode(File(goldenPath).readAsStringSync()) as Map<String, dynamic>;
    final bytes = await File(golden['input'] as String).readAsBytes();
    final actual = await pyannote.process(
      Pyannote.int16PcmBytesToFloat32(bytes),
    );
    final expected = (golden['segments'] as List).cast<Map<String, dynamic>>();

    expectValidSegments(
      actual,
      speakerCount: speakerCount,
      audioDuration: bytes.length / (2 * 16000),
    );
    expect(actual, hasLength(expected.length));

    // Cluster IDs are arbitrary, so compare IDs in order of first appearance.
    final speakerIds = <int, int>{};
    for (var index = 0; index < expected.length; index++) {
      final actualSegment = actual[index];
      final actualSpeaker = actualSegment['speaker'] as int;
      final canonicalSpeaker = speakerIds.putIfAbsent(
        actualSpeaker,
        () => speakerIds.length,
      );
      final expectedSegment = expected[index];
      expect(
        canonicalSpeaker,
        expectedSegment['speaker'],
        reason: 'speaker at segment $index changed',
      );
      // ORT providers have historically differed by up to one 33.75 ms frame.
      expect(
        actualSegment['start'],
        closeTo(expectedSegment['start'] as num, 0.05),
        reason: 'start of segment $index changed',
      );
      expect(
        actualSegment['stop'],
        closeTo(expectedSegment['stop'] as num, 0.05),
        reason: 'stop of segment $index changed',
      );
    }
  }

  test('matches the one-speaker diarization golden', () async {
    await expectMatchesGolden(
      'test/data/goldens/pyannote_one_speaker.json',
      speakerCount: 1,
    );
  });

  test('matches the two-speaker diarization golden', () async {
    // Given arbitrary WAV, convert to PCM with:
    // ffmpeg -i input.wav -acodec pcm_s16le -ac 1 -ar 16000 \
    //   -f s16le test/data/talkovergpt.pcm
    await expectMatchesGolden(
      'test/data/goldens/pyannote_two_speakers.json',
      speakerCount: 2,
    );
  });
}
