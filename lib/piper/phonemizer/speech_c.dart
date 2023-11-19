import 'dart:io';
import 'dart:typed_data';

import 'package:fonnx/piper/phonemizer/encoding_c.dart';
import 'package:fonnx/piper/phonemizer/encoding_h.dart';
import 'package:fonnx/piper/phonemizer/piper_cpp.dart';
import 'package:fonnx/piper/phonemizer/speak_lib_h.dart';
import 'package:fonnx/piper/phonemizer/synthdata_c.dart';

class TextToPhonemesResult {
  /// The next index in the input string to process.
  final int index;
  final int terminator;
  final String phonemes;

  TextToPhonemesResult({
    required this.index,
    required this.terminator,
    required this.phonemes,
  });
}

EspeakNgTextDecoder? textDecoder;
TextToPhonemesResult espeakTextToPhonemesWithTerminator(
    String textptr, int textmode, int phonememode) {
  // https://github.com/rhassy/espeak-ng/blob/0f65aa301e0d6bae5e172cc74197d32a6182200f/src/libespeak-ng/speech.c#L855
  /* phoneme_mode
      bit 1:   0=eSpeak's ascii phoneme names, 1= International Phonetic
     Alphabet (as UTF-8 characters). bit 7:   use (bits 8-23) as a tie within
     multi-letter phonemes names bits 8-23:  separator character, between
     phoneme names
   */

  textDecoder ??= EspeakNgTextDecoder(
    current: null,
    end: null,
    codepage: null,
  );

  final decodeSuccess = textDecoderDecodeStringMultibyte(
      textDecoder!, textptr, EspeakNgEncoding.utf8, textmode);
  // if (text_decoder_decode_string_multibyte(
  //         p_decoder, *textptr, translator->encoding, textmode)
  //     != ENS_OK)
  //   return NULL;

  return TextToPhonemesResult(index: 0, terminator: 0, phonemes: '');

  // TranslateClauseWithTerminator(translator, NULL, NULL, terminator);
  // *textptr = text_decoder_get_buffer(p_decoder);

  // return GetTranslatedPhonemeString(phonememode);
}

void initializePath(String path) {
  if (checkDataPath(path)) {
    return;
  }
  throw 'Failed to initialize eSpeak-ng path $path';

// #if PLATFORM_WINDOWS
// 	HKEY RegKey;
// 	unsigned long size;
// 	unsigned long var_type;
// 	unsigned char buf[sizeof(path_home)-13];

// 	if (check_data_path(getenv("ESPEAK_DATA_PATH"), 1))
// 		return;

// 	buf[0] = 0;
// 	RegOpenKeyExA(HKEY_LOCAL_MACHINE, "Software\\eSpeak NG", 0, KEY_READ, &RegKey);
// 	if (RegKey == NULL)
// 		RegOpenKeyExA(HKEY_LOCAL_MACHINE, "Software\\WOW6432Node\\eSpeak NG", 0, KEY_READ, &RegKey);
// 	size = sizeof(buf);
// 	var_type = REG_SZ;
// 	RegQueryValueExA(RegKey, "Path", 0, &var_type, buf, &size);

// 	if (check_data_path(buf, 1))
// 		return;
// #elif !defined(PLATFORM_DOS)
// 	if (check_data_path(getenv("ESPEAK_DATA_PATH"), 1))
// 		return;

// 	if (check_data_path(getenv("HOME"), 0))
// 		return;
// #endif

// 	strcpy(path_home, PATH_ESPEAK_DATA);
}

bool checkDataPath(String path) {
  if (path.isEmpty) return false;

  final dataPathExists = Directory(path).existsSync();
  if (dataPathExists) {
    return true;
  }
  debugPrint('Failed to find eSpeak-ng data path $path');
  return false;
}

bool espeakNgInitialize() {
  // int param;
  // int srate = 22050; // default sample rate 22050 Hz

  // It seems that the wctype functions don't work until the locale has been set
  // to something other than the default "C".  Then, not only Latin1 but also the
  // other characters give the correct results with iswalpha() etc.
  // if (setlocale(LC_CTYPE, "C.UTF-8") == NULL) {
  // 	if (setlocale(LC_CTYPE, "UTF-8") == NULL) {
  // 		if (setlocale(LC_CTYPE, "en_US.UTF-8") == NULL)
  // 			setlocale(LC_CTYPE, "");
  // 	}
  // }

  return true;
  // bool initialized = LoadPhData(srate);
  // if (result != ENS_OK)
  // 	return result;

  // WavegenInit(srate, 0);
  // LoadConfig();

  // espeak_VOICE *current_voice_selected = espeak_GetCurrentVoice();
  // memset(current_voice_selected, 0, sizeof(espeak_VOICE));
  // SetVoiceStack(NULL, "");
  // SynthesizeInit();
  // InitNamedata();

  // VoiceReset(0);

  // for (param = 0; param < N_SPEECH_PARAM; param++)
  // 	param_stack[0].parameter[param] = saved_parameters[param] = param_defaults[param];

  // SetParameter(espeakRATE, espeakRATE_NORMAL, 0);
  // SetParameter(espeakVOLUME, 100, 0);
  // SetParameter(espeakCAPITALS, option_capitals, 0);
  // SetParameter(espeakPUNCTUATION, option_punctuation, 0);
  // SetParameter(espeakWORDGAP, 0, 0);

  // option_phonemes = 0;
  // option_phoneme_events = 0;

  // // Seed random generator
  // espeak_srand(time(NULL));

  // return ENS_OK;
}

bool espeakNgInitializeOutput(EspeakAudioOutput outputMode, int bufferLength) {
  return true;
// 	my_mode = output_mode;
// 	out_samplerate = 0;

// #if USE_LIBPCAUDIO
// 	if (((my_mode & ENOUTPUT_MODE_SPEAK_AUDIO) == ENOUTPUT_MODE_SPEAK_AUDIO) && (my_audio == NULL))
// 		my_audio = create_audio_device_object(device, "eSpeak", "Text-to-Speech");
// #endif

// #if USE_ASYNC
// 	if ((my_mode & ENOUTPUT_MODE_SYNCHRONOUS) == 0) fifo_init();
// #endif

// 	// Don't allow buffer be smaller than safe minimum
// 	if (buffer_length < min_buffer_length)
// 		buffer_length = min_buffer_length;

// 	// allocate 2 bytes per sample
// 	// Always round up to the nearest sample and the nearest byte.
// 	int millisamples = buffer_length * samplerate;
// 	outbuf_size = (millisamples + 1000 - millisamples % 1000) / 500;
// 	out_start = (unsigned char *)realloc(outbuf, outbuf_size);
// 	if (out_start == NULL)
// 		return ENOMEM;
// 	else
// 		outbuf = out_start;

// 	// allocate space for event list.  Allow 200 events per second.
// 	// Add a constant to allow for very small buffer_length
// 	n_event_list = (buffer_length*200)/1000 + 20;
// 	espeak_EVENT *new_event_list = (espeak_EVENT *)realloc(event_list, sizeof(espeak_EVENT) * n_event_list);
// 	if (new_event_list == NULL)
// 		return ENOMEM;
// 	event_list = new_event_list;

// 	return ENS_OK;
}
