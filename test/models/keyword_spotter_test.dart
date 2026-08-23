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

        // Public-output golden: no missing, reordered, or extra detections.
        expect(detections.map((detection) => detection.phrase), [
          'rain in Spain',
          'mainly on the plain',
        ]);
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

        // Spoken forms must emit the canonical spelling. The exact number of
        // detections is decoder-dependent, so this is deliberately not a
        // golden-output comparison.
        await spotter.setKeywords(const [
          KeywordPhrase(
            'telosnex',
            spokenForms: [
              'tell us next',
              'tell us nucks',
              'tell low snacks',
              'tell us necks',
            ],
          ),
        ]);
        final telosnexPcm = File(
          'example/assets/telosnex_hotword_3times_ar16000.pcm',
        ).readAsBytesSync();
        final detectionCountBeforeAliases = detections.length;
        for (var offset = 0;
            offset < telosnexPcm.length;
            offset += chunkBytes) {
          final end = offset + chunkBytes < telosnexPcm.length
              ? offset + chunkBytes
              : telosnexPcm.length;
          await spotter.acceptPcm16(telosnexPcm.sublist(offset, end));
        }
        await spotter.finish();
        final aliasDetections =
            detections.sublist(detectionCountBeforeAliases);
        expect(aliasDetections, isNotEmpty);
        expect(
          aliasDetections.every(
            (detection) => detection.phrase == 'telosnex',
          ),
          isTrue,
        );

        // Transcription mode: report what the model heard, so users can
        // discover spokenForms for hard-to-spell names.
        final heard = await spotter.transcribePcm16(telosnexPcm);
        // Greedy transcription of three "telosnex" utterances; exact words
        // vary with decoding mode, but the acoustic gist is stable.
        expect(heard, contains('tell'));
        expect(heard, contains('snacks'));

        // Detection still works after a transcription pass.
        await spotter.setKeywords(const [KeywordPhrase('rain in Spain')]);
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
