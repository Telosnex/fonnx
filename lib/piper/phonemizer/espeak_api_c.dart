// https://github.com/rhasspy/espeak-ng/blob/0f65aa301e0d6bae5e172cc74197d32a6182200f/src/libespeak-ng/espeak_api.c#L51

/* Must be called before any synthesis functions are called.
   output: the audio data can either be played by eSpeak or passed back by the SynthCallback function.

   buflength:  The length in mS of sound buffers passed to the SynthCallback function.
            Value=0 gives a default of 60mS.
            This parameter is only used for AUDIO_OUTPUT_RETRIEVAL and AUDIO_OUTPUT_SYNCHRONOUS modes.

   path: The directory which contains the espeak-ng-data directory, or NULL for the default location.

   options: bit 0:  1=allow espeakEVENT_PHONEME events.
            bit 1:  1= espeakEVENT_PHONEME events give IPA phoneme names, not eSpeak phoneme names
            bit 15: 1=don't exit if espeak_data is not found (used for --help)

   Returns: sample rate in Hz, or -1 (EE_INTERNAL_ERROR).
*/
import 'package:fonnx/piper/phonemizer/piper_cpp.dart';
import 'package:fonnx/piper/phonemizer/speak_lib_h.dart';
import 'package:fonnx/piper/phonemizer/speech_c.dart';
import 'package:fonnx/piper/phonemizer/voices_c.dart';

bool espeakInitialize(String path) {
  // This implementation is heavily altered: eSpeak has a ton of setup for
  // doing TTS itself, but Piper only uses its phonemizer.
  initializePath(path);
  // Here, we set the "real" arguments to the only arguments Piper uses.
  const outputType = EspeakAudioOutput.synchronous;
  const bufLength = 0;
  const options = 0;
  initializePath(path);
  final subinitialize = espeakNgInitialize();
  if (!subinitialize) {
    debugPrint('Failed to initialize eSpeak-ng');
  }
  espeakNgInitializeOutput(outputType, bufLength);
  return true;
  // option_phoneme_events = (options &
  //     (espeakINITIALIZE_PHONEME_EVENTS | espeakINITIALIZE_PHONEME_IPA));

  // return espeak_ng_GetSampleRate();
}


void espeakSetVoiceByName(String name)
{
	espeakNgSetVoiceByName(name);
}