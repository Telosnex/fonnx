import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fonnx/models/pyannote/pyannote_native.dart';

void main() {
  const modelPath = 'example/assets/models/pyannote/pyannote_seg3.onnx';
  final pyannote = PyannoteNative(modelPath, "segmentation-3.0");

  test('1 speaker', () async {
    String testFilePath = 'test/data/audio_sample_ac1_ar16000.pcm';
    File file = File(testFilePath);
    final bytes = await file.readAsBytes();
    final result = await pyannote.process(pcmBytesToFloat32(bytes));
    expect(result, [
      {'speaker': 1, 'start': 0.8044375, 'stop': 4.4494375}
    ]);
  });

  test('2 speakers', () async {
    // note: given arbitrary wav, convert to pcm with:
    // ffmpeg -i input.wav -acodec pcm_s16le -ac 1 -ar 16000 output.pcm
    String testFilePath = 'test/data/talkovergpt.pcm';
    File file = File(testFilePath);
    final bytes = await file.readAsBytes();
    final result = await pyannote.process(pcmBytesToFloat32(bytes));
    expect(result, [
      {'speaker': 1, 'start': 0.8719375, 'stop': 1.5469375},
      {'speaker': 2, 'start': 3.2681875, 'stop': 6.2044375},
      {'speaker': 1, 'start': 3.9769375, 'stop': 6.2719375}
    ]);
  });
}

/// Converts raw PCM bytes to normalized float32 samples
Float32List pcmBytesToFloat32(Uint8List bytes) {
  // Convert bytes to Int16 samples
  final samples = Int16List.sublistView(bytes);

  // Convert to Float32, scaling from Int16 range to [-1, 1]
  final float32Data = Float32List(samples.length);
  for (int i = 0; i < samples.length; i++) {
    float32Data[i] = samples[i] / 32768.0; // 32768 = 2^15
  }
  return float32Data;
}
