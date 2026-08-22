import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fonnx/models/keyword_spotter/keyword_spotter.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart' as path_provider;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'keyword spotting runs through the Native Assets FFI backend',
    (_) async {
      const modelDirectoryAsset = 'assets/models/keywordSpotter';
      const filenames = [
        'encoder-epoch-12-avg-2-chunk-16-left-64.int8.onnx',
        'decoder-epoch-12-avg-2-chunk-16-left-64.int8.onnx',
        'joiner-epoch-12-avg-2-chunk-16-left-64.int8.onnx',
      ];
      final directory = await path_provider.getApplicationSupportDirectory();
      for (final filename in filenames) {
        final data = await rootBundle.load('$modelDirectoryAsset/$filename');
        final file = File(path.join(directory.path, filename));
        await file.create(recursive: true);
        await file.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true,
        );
      }

      final spotter = await KeywordSpotter.load(
        bundle: KeywordSpotterBundle.gigaSpeech3m(directory.path),
        maxActivePaths: 16,
        keywords: const [
          KeywordPhrase('rain in Spain'),
          KeywordPhrase('mainly on the plain'),
        ],
      );
      final detections = <String>[];
      final subscription = spotter.detections.listen(
        (detection) => detections.add(detection.phrase),
      );
      try {
        final pcm =
            (await rootBundle.load(
              'assets/audio_sample_ac1_ar16000.pcm',
            )).buffer.asUint8List();
        const chunkBytes = 3200;
        for (var offset = 0; offset < pcm.length; offset += chunkBytes) {
          final end =
              offset + chunkBytes < pcm.length
                  ? offset + chunkBytes
                  : pcm.length;
          await spotter.acceptPcm16(pcm.sublist(offset, end));
        }
        await spotter.finish();
        expect(
          detections,
          containsAllInOrder(<String>['rain in Spain', 'mainly on the plain']),
        );
      } finally {
        await subscription.cancel();
        await spotter.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
