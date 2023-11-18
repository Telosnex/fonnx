// // https://github.com/rhasspy/piper-phonemize/blob/master/src/phonemize.hpp

// const int clauseIntonationFullStop = 0x00000000;
// const int clauseIntonationComma = 0x00001000;
// const int clauseIntonationQuestion = 0x00002000;
// const int clauseIntonationExclamation = 0x00003000;

// const int clauseTypeClause = 0x00040000;
// const int clauseTypeSentence = 0x00080000;

// const int clausePeriod = 40 | clauseIntonationFullStop | clauseTypeSentence;
// const int clauseComma = 20 | clauseIntonationComma | clauseTypeClause;
// const int clauseQuestion = 40 | clauseIntonationQuestion | clauseTypeSentence;
// const int clauseExclamation =
//     45 | clauseIntonationExclamation | clauseTypeSentence;
// const int clauseColon = 30 | clauseIntonationFullStop | clauseTypeClause;
// const int clauseSemicolon = 30 | clauseIntonationComma | clauseTypeClause;

// typedef Phoneme = int;
// typedef PhonemeMap = Map<Phoneme, List<Phoneme>>;

// class ESpeakPhonemeConfig {
//   String voice = "en-us";

//   Phoneme period = 0x2E; // '.' CLAUSE_PERIOD
//   Phoneme comma = 0x2C; // ',' CLAUSE_COMMA
//   Phoneme question = 0x3F; // '?' CLAUSE_QUESTION
//   Phoneme exclamation = 0x21; // '!' CLAUSE_EXCLAMATION
//   Phoneme colon = 0x3A; // ':' CLAUSE_COLON
//   Phoneme semicolon = 0x3B; // ';' CLAUSE_SEMICOLON
//   Phoneme space = 0x20; // ' '

//   bool keepLanguageFlags = false;

//   PhonemeMap? phonemeMap;
// }

// // Convert the phonemize_eSpeak function into a class with a method in Dart.
// // Since it uses espeak-ng, this is only the method signature.
// class ESpeakPhonemizer {
//   void phonemizeESpeak(
//       String text, ESpeakPhonemeConfig config, List<List<Phoneme>> phonemes) {
//     // Implementation would go here
//   }
// }

// enum TextCasing {
//   casingIgnore,
//   casingLower,
//   casingUpper,
//   casingFold,
// }

// class CodepointsPhonemeConfig {
//   TextCasing casing = TextCasing.casingFold;
//   PhonemeMap? phonemeMap;
// }

// // Convert the phonemize_codepoints function into a class with a method in Dart.
// // Assume there is no FFI call and this is a direct implementation.
// class CodepointsPhonemizer {
//   void phonemizeCodepoints(String text, CodepointsPhonemeConfig config,
//       List<List<Phoneme>> phonemes) {
//     // Implementation would go here
//   }
// }

// class Phonemizer {
//   final Map<String, Map<Phoneme, List<Phoneme>>> defaultPhonemeMap = {
//     'pt-br': {
//       0x63 /* 'c' */ : [0x6B /* 'k' */]
//     }
//   };

//   void phonemizeEspeak(String text, PhonemeConfig config) {
//     var phonemes = <List<Phoneme>>[];

//     // Assuming espeak_SetVoiceByName has been replaced by Dart function call
//     bool result = espeak_SetVoiceByName(config.voice);
//     if (!result) {
//       throw Exception("Failed to set eSpeak-ng voice");
//     }

//     var phonemeMap = config.phonemeMap ?? defaultPhonemeMap[config.voice];

//     // In Dart, there's no need for a copy of the text variable
//     List<Phoneme> sentencePhonemes;
//     var inputTextPointer = text; // We will iterate over the string directly

//     // Replace espeak_TextToPhonemesWithTerminator with appropriate Dart code
//     var clausePhonemes =
//         espeakTextToPhonemesWithTerminator(inputTextPointer, config);

//     // Continue converting the rest of the function by processing the clausePhonemes
//     // ...
//   }

//   void phonemizeCodepoints(String text, PhonemeConfig config) {
//     var phonemes = <List<Phoneme>>[];

//     // ... Convert text to normalized form, handle casing, etc.
//     // If there's no built-in function in Dart, you need to import a package or implement it

//     // ... Continue converting the rest of the function by processing the text
//     // ...
//   }

//   // ... Add other methods and logic as needed
// }
