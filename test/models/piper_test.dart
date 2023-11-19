import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fonnx/models/piper/piper.dart';
import 'package:fonnx/models/piper/piper_native.dart';
import 'package:fonnx/piper/phonemizer/e2e.dart';
import 'package:fonnx/piper/piper_models.dart';
import 'package:fonnx/piper/wav_header.dart';

void main() {
  const modelJson = 'example/assets/models/piper/en_US-libritts_r-medium.json';
  const modelPath = 'example/assets/models/piper/en_US-libritts_r-medium.onnx';
  final piper = PiperNative(modelPath);
  test('e2e', () async {
    e2e();
  });
  test('hello world', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final config = await Piper.loadConfig(modelJson);
    expect(config, isNotNull);
    print('config: $config');

    print('=== phonemeIdMap ===');

    print(config?.phonemeIdMap);
    const string =
        'hello world hello world hello world hello world hello world hello world hello world';
    final characters = string.split('');
    final phonemes = characters
        .map((e) => config?.phonemeIdMap?[e])
        .expand((e) => e ?? <int>[])
        .toList(growable: false);
    expect(phonemes.length, 83);
    final bytes = await piper.getTts(
      config: config!,
      phonemes: phonemes,
    );
    final synthesisConfig = PiperSynthesisConfig(
      noiseScale: config.inference!.noiseScale!,
      lengthScale: config.inference!.lengthScale!,
      noiseW: config.inference!.noiseW!,
      speakerId: 0,
    );
    expect(bytes.length, greaterThan(4000));
    expect(bytes.length, lessThan(100000));
    final signedInts = convertFloat32ToInt16(bytes);
    final header = WavHeader(
      sampleWidth: synthesisConfig.sampleWidth,
      numSamples: signedInts.length ~/ synthesisConfig.sampleWidth,
      numChannels: synthesisConfig.channels,
      sampleRate: synthesisConfig.sampleRate,
    );
    final writeFile = File('test/ephemeral/hello_world.wav');
    await writeWavFile(writeFile.path, header, signedInts);

    // final synthesisConfig = config?.audio.
    // writeWavHeader(config.audio?.sampleRate ?? 22050, synthesisConfig.sampleWidth,
    //        synthesisConfig.channels, (int32_t)audioBuffer.size(),
    //        audioFile);
  });

  test('prephonemized?', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final config = await Piper.loadConfig(modelJson);
    expect(config, isNotNull);
    print('config: $config');

    print('=== phonemeIdMap ===');

    print(config?.phonemeIdMap);

    final string = 'foʊnmaɪzɚ';

    final characters = string.split('');
    final phonemes = characters
        .map((e) => config?.phonemeIdMap?[e])
        .expand((e) => e == null ? <int>[0] : <int>[0, ...e])
        .toList(growable: false);
    expect(phonemes.length, 15);
    final bytes = await piper.getTts(
      config: config!,
      phonemes: [1, 0, ...phonemes,0,2],
    );
    final synthesisConfig = PiperSynthesisConfig(
      noiseScale: config.inference!.noiseScale!,
      lengthScale: config.inference!.lengthScale!,
      noiseW: config.inference!.noiseW!,
      speakerId: 0,
    );
    expect(bytes.length, greaterThan(4000));
    expect(bytes.length, lessThan(100000));
    final signedInts = convertFloat32ToInt16(bytes);
    final header = WavHeader(
      sampleWidth: synthesisConfig.sampleWidth,
      numSamples: signedInts.length ~/ synthesisConfig.sampleWidth,
      numChannels: synthesisConfig.channels,
      sampleRate: synthesisConfig.sampleRate,
    );
    final writeFile = File('test/ephemeral/hello_world.wav');
    await writeWavFile(writeFile.path, header, signedInts);
  });

  test('Piper Phonemize Test', () async {
    // https://github.com/rhasspy/piper-phonemize/blob/fccd4f335aa68ac0b72600822f34d84363daa2bf/README.md?plain=1#L16
    final ids = [
      1,
      0,
      41,
      0,
      74,
      0,
      31,
      0,
      3,
      0,
      74,
      0,
      38,
      0,
      3,
      0,
      50,
      0,
      26,
      0,
      120,
      0,
      102,
      0,
      41,
      0,
      60,
      0,
      3,
      0,
      32,
      0,
      120,
      0,
      61,
      0,
      31,
      0,
      32,
      0,
      4,
      0,
      2
    ];
    final config = await Piper.loadConfig(modelJson);
    expect(config, isNotNull);
    if (config == null) {
      return;
    }

    final bytes = await piper.getTts(
      config: config,
      phonemes: ids,
    );
    final synthesisConfig = PiperSynthesisConfig(
      noiseScale: config.inference!.noiseScale!,
      lengthScale: config.inference!.lengthScale!,
      noiseW: config.inference!.noiseW!,
      speakerId: 0,
    );
    expect(bytes.length, greaterThan(4000));
    expect(bytes.length, lessThan(100000));
    final signedInts = convertFloat32ToInt16(bytes);
    final header = WavHeader(
      sampleWidth: synthesisConfig.sampleWidth,
      numSamples: signedInts.length ~/ synthesisConfig.sampleWidth,
      numChannels: synthesisConfig.channels,
      sampleRate: synthesisConfig.sampleRate,
    );
    final writeFile = File('test/ephemeral/this_is_another_test.wav');
    await writeWavFile(writeFile.path, header, signedInts);
  });
}

Future<void> writeWavFile(
    String filePath, WavHeader header, Int16List samples) async {
  final file = File(filePath);
  final bytesBuilder = BytesBuilder();

  // Write the WAV header bytes
  bytesBuilder.add(header.getBytes());

  // Write the sample data (little endian for each sample)
  for (var sample in samples) {
    // Int16List is already in little-endian format on little-endian architectures
    // If you are working in big-endian system, do need to convert endianess
    bytesBuilder.addByte((sample & 0xff));
    bytesBuilder.addByte((sample >> 8) & 0xff);
  }

  // Once all bytes are added, take the Uint8List and write it to file
  await file.writeAsBytes(bytesBuilder.takeBytes(), mode: FileMode.write);
}
