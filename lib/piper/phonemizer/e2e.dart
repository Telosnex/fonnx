import 'dart:convert';
import 'dart:io';

import 'package:fonnx/piper/phonemizer/espeak_api_c.dart';
import 'package:fonnx/piper/phonemizer/speech_c.dart';

final espeakPHONEMES_IPA = 0x02;
final espeakCHARS_AUTO = 0;

// Intonation constants
const int CLAUSE_INTONATION_FULL_STOP = 0x00000000;
const int CLAUSE_INTONATION_COMMA = 0x00001000;
const int CLAUSE_INTONATION_QUESTION = 0x00002000;
const int CLAUSE_INTONATION_EXCLAMATION = 0x00003000;
const int CLAUSE_INTONATION_NONE = 0x00004000;

// Type constants
const int CLAUSE_TYPE_NONE = 0x00000000;
const int CLAUSE_TYPE_EOF = 0x00010000;
const int CLAUSE_TYPE_CLAUSE = 0x00040000;
const int CLAUSE_TYPE_SENTENCE = 0x00080000;

// Combined clause constants
const int CLAUSE_NONE = 0 | CLAUSE_INTONATION_NONE | CLAUSE_TYPE_NONE;
const int CLAUSE_PARAGRAPH =
    70 | CLAUSE_INTONATION_FULL_STOP | CLAUSE_TYPE_SENTENCE;
const int CLAUSE_EOF =
    40 | CLAUSE_INTONATION_FULL_STOP | CLAUSE_TYPE_SENTENCE | CLAUSE_TYPE_EOF;
const int CLAUSE_PERIOD =
    40 | CLAUSE_INTONATION_FULL_STOP | CLAUSE_TYPE_SENTENCE;
const int CLAUSE_COMMA = 20 | CLAUSE_INTONATION_COMMA | CLAUSE_TYPE_CLAUSE;
const int CLAUSE_QUESTION =
    40 | CLAUSE_INTONATION_QUESTION | CLAUSE_TYPE_SENTENCE;
const int CLAUSE_EXCLAMATION =
    45 | CLAUSE_INTONATION_EXCLAMATION | CLAUSE_TYPE_SENTENCE;
const int CLAUSE_COLON = 30 | CLAUSE_INTONATION_FULL_STOP | CLAUSE_TYPE_CLAUSE;
const int CLAUSE_SEMICOLON = 30 | CLAUSE_INTONATION_COMMA | CLAUSE_TYPE_CLAUSE;

// The expected phonemes as a multiline string
const String EXPECTED_PHONEMES = """ðˈɪs, ˌaɪˌɛsˈeɪ; ɡˈʊd: tˈɛst!
ˌoʊkˈeɪ?
""";

// https://github.com/rhasspy/espeak-ng/blob/0f65aa301e0d6bae5e172cc74197d32a6182200f/python_test.py#L7
void e2e() {
  espeakInitialize('${Directory.current.path}/lib/piper/espeak-ng-data');

  final voice = 'en-us';
  espeakSetVoiceByName(voice);

  // Should split into 3 sentences, highlighting each punctuation type.
  final text = 'this, I.S. a; good: test! ok?';
  final textBytes = utf8.encode(text);
  final phonemeFlags = espeakPHONEMES_IPA;
  final textFlags = espeakCHARS_AUTO;
  int index = 0;
  var allPhonemes = '';
  while (index < textBytes.length) {
    final remainingSubstring = text.substring(index);
    final result = espeakTextToPhonemesWithTerminator(
        remainingSubstring, textFlags, phonemeFlags);

    final clausePhonemes = result.phonemes;
    allPhonemes += clausePhonemes;
    final terminator = result.terminator;
    // The following would depend on how clauses are determined in your application
    if (terminator == CLAUSE_EXCLAMATION) {
      allPhonemes += '!';
    } else if (terminator == CLAUSE_QUESTION) {
      allPhonemes += '?';
    } else if (terminator == CLAUSE_COMMA) {
      allPhonemes += ',';
    } else if (terminator == CLAUSE_COLON) {
      allPhonemes += ':';
    } else if (terminator == CLAUSE_SEMICOLON) {
      allPhonemes += ';';
    } else if (terminator == CLAUSE_PERIOD) {
      allPhonemes += '.';
    }

    if ((terminator & CLAUSE_TYPE_SENTENCE) == CLAUSE_TYPE_SENTENCE) {
      allPhonemes += '\n';
    } else {
      allPhonemes += '';
    }

    if (allPhonemes == EXPECTED_PHONEMES) {
      print("It works!");
    } else {
      print("Expected: $EXPECTED_PHONEMES\nGot: $allPhonemes");
    }
  }
}
