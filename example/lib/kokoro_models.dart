import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:fonnx/models/kokoro/kokoro.dart';
import 'package:fonnx/runtime_models.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart' as path_provider;

/// Reports a model download: bytes received, and the total if known.
typedef KokoroDownloadProgress = void Function(int received, int total);

/// The voices of the example: one American, one British.
const kokoroExampleVoices = ['af_heart', 'bf_emma'];

/// A Kokoro bundle of files from the pinned Hugging Face catalog, about
/// 200 MB. On native platforms, the files are downloaded once into the
/// application support directory, and their SHA-256 checked. On web, the
/// Kokoro Worker loads them from the pinned URLs.
Future<KokoroBundle> kokoroExampleBundle({
  KokoroDownloadProgress? onProgress,
}) async {
  // The layout of tool/kokoro/prepare_bundle.dart, which the catalog uses.
  final layout = KokoroBundle.fromDirectory(
    'kokoro',
    voiceNames: kokoroExampleVoices,
  );
  final paths = [
    layout.prosodyModel,
    layout.decoderModel,
    layout.spacyConfig,
    layout.spacyWeights,
    layout.usGold,
    layout.usSilver,
    layout.gbGold,
    layout.gbSilver,
    layout.fallbackModel,
    layout.fallbackConfig,
    for (final voice in layout.voices.values) voice.path,
  ];
  final locations = <String, String>{};
  if (kIsWeb) {
    for (final p in paths) {
      locations[p] = runtimeModelFile(p).url;
    }
  } else {
    final directory = Directory(
      path.join(
        (await path_provider.getApplicationSupportDirectory()).path,
        'models',
      ),
    );
    int size(String p) => runtimeModelFile(p).bytes ?? 0;
    final total = paths.fold(0, (sum, p) => sum + size(p));
    var done = 0;
    for (final p in paths) {
      final file = await ensureFonnxRuntimeModel(
        p,
        directory,
        onProgress: (received, _) => onProgress?.call(done + received, total),
      );
      done += size(p);
      onProgress?.call(done, total);
      locations[p] = file.path;
    }
  }
  return KokoroBundle(
    prosodyModel: locations[layout.prosodyModel]!,
    decoderModel: locations[layout.decoderModel]!,
    spacyConfig: locations[layout.spacyConfig]!,
    spacyWeights: locations[layout.spacyWeights]!,
    usGold: locations[layout.usGold]!,
    usSilver: locations[layout.usSilver]!,
    gbGold: locations[layout.gbGold]!,
    gbSilver: locations[layout.gbSilver]!,
    fallbackModel: locations[layout.fallbackModel]!,
    fallbackConfig: locations[layout.fallbackConfig]!,
    voices: {
      for (final MapEntry(:key, :value) in layout.voices.entries)
        key: KokoroVoice(
          path: locations[value.path]!,
          language: value.language,
        ),
    },
  );
}
