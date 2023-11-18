import 'package:flutter/foundation.dart';
import 'package:fonnx/piper/phonemizer/espeak_api_c.dart';
import 'package:fonnx/piper/phonemizer/speak_lib_h.dart';
import 'package:fonnx/piper/piper_models.dart';

void debugPrint(String string) {
  if (kDebugMode) {
    print(string);
  }
}


void initialize(PiperConfig config) {
  // https://github.com/rhasspy/piper/blob/38917ffd8c0e219c6581d73e07b30ef1d572fce1/src/cpp/piper.cpp#L216
  if (config.espeak != null) {
    // Set up espeak-ng for calling espeak_TextToPhonemesWithTerminator
    // See: https://github.com/rhasspy/espeak-ng
    debugPrint('Initializing eSpeak');
    final result = espeakInitialize(/* config.eSpeakDataPath */ '');
    if (!result) {
      throw "Failed to initialize eSpeak-ng";
    }
    debugPrint("Initialized eSpeak");
  }

  // // Load onnx model for libtashkeel
  // // https://github.com/mush42/libtashkeel/
  // if (config.useTashkeel) {
  //   spdlog::debug("Using libtashkeel for diacritization");
  //   if (!config.tashkeelModelPath) {
  //     throw std::runtime_error("No path to libtashkeel model");
  //   }

  //   spdlog::debug("Loading libtashkeel model from {}",
  //                 config.tashkeelModelPath.value());
  //   config.tashkeelState = std::make_unique<tashkeel::State>();
  //   tashkeel::tashkeel_load(config.tashkeelModelPath.value(),
  //                           *config.tashkeelState);
  //   spdlog::debug("Initialized libtashkeel");
  // }

  debugPrint("Initialized piper");
}