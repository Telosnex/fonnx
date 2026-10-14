import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:fonnx/models/nemoAsr/nemo_asr.dart';
import 'package:fonnx/models/senseVoice/sense_voice.dart';
import 'package:fonnx/models/whisper/whisper.dart';
import 'package:fonnx/runtime_models.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart' as path_provider;

/// Transcribes 16-bit little-endian PCM, mono, 16 kHz.
typedef SttInference = Future<String> Function(Uint8List pcm);

/// Reports a model download: bytes received, and the total if known.
typedef DownloadProgress = void Function(int received, int? total);

/// The speech-to-text models of the example.
enum SttModel {
  fastConformer(
    'NVIDIA FastConformer',
    '132 MB. English, German, French, Spanish, Italian, Polish, Russian, '
        'Ukrainian, Croatian, Belarusian. By NVIDIA, CC-BY-4.0.',
  ),
  senseVoice(
    'SenseVoice',
    '239 MB. Mandarin, Cantonese, Japanese, Korean, English. By Alibaba, '
        'FunASR Model License.',
  ),
  whisperTiny(
    'Whisper Tiny',
    '151 MB. Many languages, but weak outside English. By OpenAI, MIT.',
  );

  const SttModel(this.label, this.description);

  final String label;
  final String description;

  /// Whether the first use downloads the model. Whisper Tiny is bundled.
  bool get downloads => this != whisperTiny;

  /// Loads the model, downloading it first if needed, and returns its
  /// inference function. The models detect the language.
  Future<SttInference> load({DownloadProgress? onProgress}) async {
    switch (this) {
      case whisperTiny:
        return Whisper.load(await getWhisperBundle()).doInference;
      case fastConformer:
        final model = await _runtimeModel(
          'nemoAsr/fastconformer_ctc_multilingual_int8.onnx',
          onProgress,
        );
        return NemoAsr.load(
          NemoAsrBundle.fastConformerCtcMultilingualFile(model),
        ).doInference;
      case senseVoice:
        final tokens = await _runtimeModel(
          'senseVoice/sense_voice_small_tokens.txt',
          null,
        );
        final model = await _runtimeModel(
          'senseVoice/sense_voice_small_int8.onnx',
          onProgress,
        );
        final senseVoice = SenseVoice.load(
          SenseVoiceBundle(modelPath: model, tokensPath: tokens),
        );
        return (pcm) => senseVoice.doInference(pcm);
    }
  }
}

/// A model file that is too large to bundle with the example. On native
/// platforms, it is downloaded once into the application support directory
/// from its pinned Hugging Face commit, and its SHA-256 checked. On web, it
/// loads straight from the pinned URL.
Future<String> _runtimeModel(
  String modelPath,
  DownloadProgress? onProgress,
) async {
  if (kIsWeb) {
    return nativePrebuiltRuntimeFiles[path.basename(modelPath)]!.url;
  }
  final support = await path_provider.getApplicationSupportDirectory();
  final file = await ensureFonnxRuntimeModel(
    modelPath,
    Directory(path.join(support.path, 'models')),
    onProgress: onProgress,
  );
  return file.path;
}

/// Whisper tiny from the example's assets. Native platforms need files, so
/// the models are copied to the application support directory.
Future<WhisperBundle> getWhisperBundle() async {
  if (kIsWeb) return WhisperBundle.tiny('assets/models/whisper');
  final encoderPath = await getWhisperModelPath('whisper_tiny_encoder.onnx');
  await getWhisperModelPath('whisper_tiny_decoder.onnx');
  return WhisperBundle.tiny(path.dirname(encoderPath));
}

Future<String> getWhisperModelPath(String modelFilenameWithExtension) async {
  if (kIsWeb) {
    return 'assets/models/whisper/$modelFilenameWithExtension';
  }
  final assetCacheDirectory = await path_provider
      .getApplicationSupportDirectory();
  final modelPath = path.join(
    assetCacheDirectory.path,
    modelFilenameWithExtension,
  );

  File file = File(modelPath);
  bool fileExists = await file.exists();
  final fileLength = fileExists ? await file.length() : 0;

  // Do not use path package / path.join for paths.
  // After testing on Windows, it appears that asset paths are _always_ Unix style, i.e.
  // use /, but path.join uses \ on Windows.
  final assetPath =
      'assets/models/whisper/${path.basename(modelFilenameWithExtension)}';
  final assetByteData = await rootBundle.load(assetPath);
  final assetLength = assetByteData.lengthInBytes;
  final fileSameSize = fileLength == assetLength;
  if (!fileExists || !fileSameSize) {
    debugPrint(
      'Copying model to $modelPath. Why? Either the file does not exist (${!fileExists}), '
      'or it does exist but is not the same size as the one in the assets '
      'directory. (${!fileSameSize})',
    );
    debugPrint('About to get byte data for $modelPath');

    List<int> bytes = assetByteData.buffer.asUint8List(
      assetByteData.offsetInBytes,
      assetByteData.lengthInBytes,
    );
    debugPrint('About to copy model to $modelPath');
    try {
      if (!fileExists) {
        await file.create(recursive: true);
      }
      await file.writeAsBytes(bytes, flush: true);
    } catch (e) {
      debugPrint('Error writing bytes to $modelPath: $e');
      rethrow;
    }
    debugPrint('Copied model to $modelPath');
  }

  return modelPath;
}
