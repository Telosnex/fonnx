import 'package:fonnx/piper/phonemizer/speak_lib_h.dart';

void espeakNgSetVoiceByName(String name)
{
	EspeakVoice? v;
	int ix;
	EspeakVoice? voiceSelector;
	String buf = name;

	final String variantName = ExtractVoiceVariantName(buf, 0, 1);

	buf = buf.toLowerCase();
  voiceSelector = EspeakVoice(name: name, languages: '', identifier: '', gender: Gender.none);
  // TODO: Came back after couple hours and realized that I don't know what this is doing.
	// first check for a voice with this filename
	// This may avoid the need to call espeak_ListVoices().

	// if (LoadVoice(buf, 1) != NULL) {
	// 	if (variant_name[0] != 0)
	// 		LoadVoice(variant_name, 2);

	// 	DoVoiceChange(voice);
	// 	voice_selector.languages = voice->language_name;
	// 	SetVoiceStack(&voice_selector, variant_name);
	// 	return ENS_OK;
	// }

	// if (n_voices_list == 0)
	// 	espeak_ListVoices(NULL); // create the voices list

	// if ((v = SelectVoiceByName(voices_list, buf)) != NULL) {
	// 	if (LoadVoice(v->identifier, 0) != NULL) {
	// 		if (variant_name[0] != 0)
	// 			LoadVoice(variant_name, 2);
	// 		DoVoiceChange(voice);
	// 		voice_selector.languages = voice->language_name;
	// 		SetVoiceStack(&voice_selector, variant_name);
	// 		return ENS_OK;
	// 	}
	// }
	// return ENS_VOICE_NOT_FOUND;
}

String ExtractVoiceVariantName(String? vname, int variant_num, int add_dir)
{
  if (vname == null) {
    return '';
  }

  String variantName = '';
  String variantPrefix = '!v/'; // Assuming PATHSEP is a forward slash '/'
  int variantNum = 0;

  // If `add_dir` is not used in Dart as it's not included in your snippet.
  // variantPrefix could be set to an empty string conditionally.

  int plusIndex = vname.indexOf('+');
  if (plusIndex != -1) {
    // The voice name has a +variant suffix.
    variantNum = 0;
    String prefix = vname.substring(0, plusIndex);
    String suffix = vname.substring(plusIndex + 1);

    if (int.tryParse(suffix) != null) {
      variantNum = int.parse(suffix); // variant number.
    } else {
      variantName = '$variantPrefix$suffix'; // voice variant name, not number.
    }

    vname = prefix; // remove the suffix from the voice name.
  }

  if (variantNum > 0) {
    if (variantNum < 10) {
      variantName = '${variantPrefix}m$variantNum'; // male.
    } else {
      variantNum -= 10;
      variantName = '${variantPrefix}f$variantNum'; // female
    }
  }

  return variantName;
  // ORIGINAL:
	// Remove any voice variant suffix (name or number) from a voice name
	// Returns the voice variant name

	// static char variant_name[40];
	// char variant_prefix[5];

	// MAKE_MEM_UNDEFINED(&variant_name, sizeof(variant_name));
	// variant_name[0] = 0;
	// sprintf(variant_prefix, "!v%c", PATHSEP);
	// if (add_dir == 0)
	// 	variant_prefix[0] = 0;

	// if (vname != NULL) {
	// 	char *p;
	// 	if ((p = strchr(vname, '+')) != NULL) {
	// 		// The voice name has a +variant suffix
	// 		variant_num = 0;
	// 		*p++ = 0; // delete the suffix from the voice name
	// 		if (IsDigit09(*p))
	// 			variant_num = atoi(p); // variant number
	// 		else {
	// 			// voice variant name, not number
	// 			sprintf(variant_name, "%s%s", variant_prefix, p);
	// 		}
	// 	}
	// }

	// if (variant_num > 0) {
	// 	if (variant_num < 10)
	// 		sprintf(variant_name, "%sm%d", variant_prefix, variant_num); // male
	// 	else
	// 		sprintf(variant_name, "%sf%d", variant_prefix, variant_num-10); // female
	// }

	// return variant_name;
}