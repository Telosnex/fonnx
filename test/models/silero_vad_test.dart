import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fonnx/models/sileroVad/silero_vad.dart';

void main() {
  test('Silero VAD v6.2.1 matches official streaming frame contract', () async {
    const modelPath = 'example/assets/models/sileroVad/silero_vad_v6.2.1.onnx';
    final pcm =
        File('test/data/audio_sample_ac1_ar16000.pcm').readAsBytesSync();
    final vad = SileroVad.load(modelPath);

    final whole = await vad.doInference(pcm);
    final wholeOutput = whole['output'] as Float32List;

    expect(whole.keys, containsAll(<String>['output', 'state', 'context']));
    expect(wholeOutput, hasLength(155));
    expect(wholeOutput.first, closeTo(0.0271902382, 1e-5));
    expect(wholeOutput.reduce((a, b) => a > b ? a : b), greaterThan(0.999));
    expect(whole['state'], isA<Float32List>());
    expect(whole['state'], hasLength(256));
    expect(whole['context'], isA<Float32List>());
    expect(whole['context'], hasLength(64));

    // Passing the first result into the second call must be equivalent to one
    // uninterrupted call when the split lies on a 512-sample frame boundary.
    const firstSamples = 512 * 50;
    final splitBytes = firstSamples * 2;
    final first = await vad.doInference(
      Uint8List.sublistView(pcm, 0, splitBytes),
    );
    final second = await vad.doInference(
      Uint8List.sublistView(pcm, splitBytes),
      previousState: first,
    );
    final splitOutput = Float32List.fromList(<double>[
      ...(first['output'] as Float32List),
      ...(second['output'] as Float32List),
    ]);
    expect(splitOutput, orderedEquals(wholeOutput));
  });
}
