import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fonnx/models/keyword_spotter/keyword_spotter.dart';

void main() {
  const modelDirectory = 'example/assets/models/keywordSpotter';

  test(
    'detects runtime English phrases in streaming PCM',
    () async {
      final spotter = await KeywordSpotter.load(
        bundle: KeywordSpotterBundle.gigaSpeech3m(modelDirectory),
        keywords: const [
          KeywordPhrase('rain in Spain'),
          KeywordPhrase('mainly on the plain'),
          KeywordPhrase('hey telosnex'),
        ],
      );
      final detections = <KeywordDetection>[];
      final subscription = spotter.detections.listen(detections.add);
      try {
        final pcm = await File(
          'test/data/audio_sample_ac1_ar16000.pcm',
        ).readAsBytes();
        const chunkBytes = 3200; // 100 ms of mono 16-bit 16 kHz PCM.
        for (var offset = 0; offset < pcm.length; offset += chunkBytes) {
          final end = offset + chunkBytes < pcm.length
              ? offset + chunkBytes
              : pcm.length;
          await spotter.acceptPcm16(pcm.sublist(offset, end));
        }
        await spotter.finish();

        expect(
          detections.map((detection) => detection.phrase),
          containsAllInOrder(['rain in Spain', 'mainly on the plain']),
        );
        expect(
          detections.where((detection) => detection.phrase == 'hey telosnex'),
          isEmpty,
        );

        final previousDetectionCount = detections.length;
        await spotter.setKeywords(const [KeywordPhrase('rain in Spain')]);
        for (var offset = 0; offset < pcm.length; offset += chunkBytes) {
          final end = offset + chunkBytes < pcm.length
              ? offset + chunkBytes
              : pcm.length;
          await spotter.acceptPcm16(pcm.sublist(offset, end));
        }
        await spotter.finish();
        final afterReplacement = detections.sublist(previousDetectionCount);
        expect(afterReplacement.map((detection) => detection.phrase), [
          'rain in Spain',
        ]);

        // Transcription mode: report what the model heard, so users can
        // discover spokenForms for hard-to-spell names.
        final telosnexPcm = File(
          'example/assets/telosnex_hotword_3times_ar16000.pcm',
        ).readAsBytesSync();
        final heard = await spotter.transcribePcm16(telosnexPcm);
        // Greedy transcription of three "telosnex" utterances; exact words
        // vary with decoding mode, but the acoustic gist is stable.
        expect(heard, contains('tell'));
        expect(heard, contains('snacks'));

        // Detection still works after a transcription pass.
        final detectionCountBeforeReuse = detections.length;
        for (var offset = 0; offset < pcm.length; offset += chunkBytes) {
          final end = offset + chunkBytes < pcm.length
              ? offset + chunkBytes
              : pcm.length;
          await spotter.acceptPcm16(pcm.sublist(offset, end));
        }
        await spotter.finish();
        expect(
          detections
              .sublist(detectionCountBeforeReuse)
              .map((detection) => detection.phrase),
          ['rain in Spain'],
        );
      } finally {
        await subscription.cancel();
        await spotter.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
  test(
    'serializes chunks and recreates Native Asset sessions',
    () async {
      final pcm = await File(
        'test/data/audio_sample_ac1_ar16000.pcm',
      ).readAsBytes();
      const chunkBytes = 3200;

      for (var iteration = 0; iteration < 2; iteration++) {
        final spotter = await KeywordSpotter.load(
          bundle: KeywordSpotterBundle.gigaSpeech3m(modelDirectory),
          keywords: const [KeywordPhrase('rain in Spain')],
        );
        final detections = <KeywordDetection>[];
        final subscription = spotter.detections.listen(detections.add);
        try {
          final pending = <Future<void>>[];
          for (var offset = 0; offset < pcm.length; offset += chunkBytes) {
            final end = offset + chunkBytes < pcm.length
                ? offset + chunkBytes
                : pcm.length;
            // Do not await here: the public queue must preserve microphone
            // callback order and apply backpressure internally.
            pending.add(spotter.acceptPcm16(pcm.sublist(offset, end)));
          }
          await Future.wait(pending);
          await spotter.finish();
          expect(
            detections.map((detection) => detection.phrase),
            contains('rain in Spain'),
          );
        } finally {
          await subscription.cancel();
          await spotter.close();
        }
        expect(() => spotter.acceptSamples(Float32List(1)), throwsStateError);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
