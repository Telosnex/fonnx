// https://github.com/rhasspy/espeak-ng/blob/master/src/libespeak-ng/translate.c

import 'dart:convert';

import 'package:ffi/ffi.dart';
import 'package:fonnx/piper/phonemizer/common_c.dart';
import 'package:fonnx/piper/phonemizer/read_clause_c.dart';
import 'package:fonnx/piper/phonemizer/translate_h.dart';

class TranslateClauseResult {
  final int tone;
  final int terminator;
  final String? voiceChange;

  TranslateClauseResult({
    required this.tone,
    required this.terminator,
    this.voiceChange,
  });
}

 int maxClausePause = 0;

int countSentences = 0;
int countWords = 0;
int endCharacterPosition = 0;
int skipSentences = 0;
List<int> skipMarker = [0];
int skipWords = 0;
int skipCharacters = 0;
bool skippingText = false;
bool newSentence = true;
int optionSayas = 0;
int optionSayas2 = 0;
int optionEmphasis = 0;
int wordEmphasis = 0;
int embeddedFlag = 0;

void InitText(int control)
{
	countSentences = 0;
	countWords = 0;
	endCharacterPosition = 0;
	skipSentences = 0;
	skipMarker[0] = 0;
	skipWords = 0;
	skipCharacters = 0;
	skippingText = false;
	newSentence = true;

	optionSayas = 0;
	optionSayas2 = 0;
	optionEmphasis = 0;
	wordEmphasis = 0;
	embeddedFlag = 0;

// TODO:
	// InitText2();

	// if ((control & espeakKEEP_NAMEDATA) == 0)
	// 	InitNamedata();
}

TranslateClauseResult TranslateClauseWithTerminator(Translator tr, String source) {
  int toneOut = -1;
  int terminatorOut = -1;

  int ix;
  int c;
  int cc = 0;
  int sourceIndex = 0;
  int sourceIndexWord = 0;
  int prevIn;
  int prevOut = utf8.encode(' ').first;
  int prevInSave = 0;
  int nextIn;
  int nextInNBytes;
  int charInserted = 0;
  int clausePause;
  int prePauseAdd = 0;
  int allUpperCase = FLAG_ALL_UPPER;
  int alphaCount = 0;
  bool finished = false;
  bool singleQuoted = false;
  bool phonemeMode = false;
  int dictFlags = 0; // returned from dictionary lookup
  int wordFlags; // set here
  int nextWordFlags;
  bool newSentence2;
  int embeddedCount = 0;
  int letterCount = 0;
  bool spaceInserted = false;
  bool syllableMarked = false;
  bool decimalSepCount = false;
  String? word;

  int j, k;
  int nDigits;
  int charixTop = 0;

  List<int> charix = List.filled(N_TR_SOURCE + 4, 0);
  List<WordTab> words = List.filled(N_CLAUSE_WORDS, WordTab());
  String voiceChangeName = '';
  int wordCount = 0; // index into words

  List<int> sbuf = List.filled(N_TR_SOURCE, 0);

  int terminator;
  int tone;

  if (tr == null) {
    return TranslateClauseResult(tone: 0, terminator: 0);
  }

  int embeddedIx = 0;
  int embeddedRead = 0;
  int prePause = 0;
  bool anyStressedWords = false;

  var clauseStartChar = countCharacters;
  if (clauseStartChar < 0) {
    clauseStartChar = 0;
  }

  var clauseStartWord = countWords + 1;

  for (ix = 0; ix < N_TR_SOURCE; ix++) {
    charix[ix] = 0;
  }
  terminator = ReadClause(
      tr, source, charix, charixTop, N_TR_SOURCE, tone, voiceChangeName);
  if (tone == 0) {
    toneOut = terminator &
        CLAUSE_INTONATION_TYPE >>
            12; // tone type not overridden in ReadClause, use default
  } else {
    toneOut = tone; // override tone type
  }

  charix[charixTop + 1] = 0;
  charix[charixTop + 2] = 0x7fff;
  charix[charixTop + 3] = 0;

  clausePause = (terminator & CLAUSE_PAUSE) * 10; // mS
  if ((terminator & CLAUSE_PAUSE_LONG) != 0) {
    clausePause = clausePause * 32; // pause value is *320mS not *10mS
  }

 int p = 0;
 final sourceBytes = utf8.encode(source);
  for (int p = 0; p < sourceBytes.length; p++) {
    if (!isspace2(sourceBytes[p])) {
      break;
    }
  }
  if (p == 0) {
    // No characters except spaces. This is not a sentence.
    // Don't add this pause, just make up the previous pause to this value;
    clausePause -= maxClausePause;
    if (clausePause < 0) {
      clausePause = 0;
    }

    if (newSentence) {
      terminator |= CLAUSE_TYPE_SENTENCE; // carry forward an end-of-sentence indicator
    }
    maxClausePause += clausePause;
    newSentence2 = false;
  } else {
    maxClausePause = clausePause;
    newSentence2 = newSentence;
  }

  if 
// Same as TranslateClause except we also get the clause terminator used (full stop, comma, etc.).
// Used by espeak_TextToPhonemesWithTerminator.

  // int ix;
  // int c;
  // int cc = 0;
  // unsigned int source_index = 0;
  // int source_index_word = 0;
  // int prev_in;
  // int prev_out = ' ';
  // int prev_in_save = 0;
  // int next_in;
  // int next_in_nbytes;
  // int char_inserted = 0;
  // int clause_pause;
  // int pre_pause_add = 0;
  // int all_upper_case = FLAG_ALL_UPPER;
  // int alpha_count = 0;
  // bool finished = false;
  // bool single_quoted = false;
  // bool phoneme_mode = false;
  // int dict_flags = 0; // returned from dictionary lookup
  // int word_flags; // set here
  // int next_word_flags;
  // bool new_sentence2;
  // int embedded_count = 0;
  // int letter_count = 0;
  // bool space_inserted = false;
  // bool syllable_marked = false;
  // bool decimal_sep_count = false;
  // char *word;
  // char *p;
  // int j, k;
  // int n_digits;
  // int charix_top = 0;

  // short charix[N_TR_SOURCE+4];
  // WORD_TAB words[N_CLAUSE_WORDS];
  // static char voice_change_name[40];
  // int word_count = 0; // index into words

  // char sbuf[N_TR_SOURCE];

  // int terminator;
  // int tone;

  // if (tr == NULL)
  // 	return;

  // MAKE_MEM_UNDEFINED(&voice_change_name, sizeof(voice_change_name));

  // embedded_ix = 0;
  // embedded_read = 0;
  // pre_pause = 0;
  // any_stressed_words = false;

  // if ((clause_start_char = count_characters) < 0)
  // 	clause_start_char = 0;
  // clause_start_word = count_words + 1;

  // for (ix = 0; ix < N_TR_SOURCE; ix++)
  // 	charix[ix] = 0;
  // MAKE_MEM_UNDEFINED(&source, sizeof(source));
  // terminator = ReadClause(tr, source, charix, &charix_top, N_TR_SOURCE, &tone, voice_change_name);

  // if (terminator_out != NULL) {
  // 	*terminator_out = terminator;
  // }

  // if (tone_out != NULL) {
  // 	if (tone == 0)
  // 		*tone_out = (terminator & CLAUSE_INTONATION_TYPE) >> 12; // tone type not overridden in ReadClause, use default
  // 	else
  // 		*tone_out = tone; // override tone type
  // }

  // charix[charix_top+1] = 0;
  // charix[charix_top+2] = 0x7fff;
  // charix[charix_top+3] = 0;

  // clause_pause = (terminator & CLAUSE_PAUSE) * 10; // mS
  // if (terminator & CLAUSE_PAUSE_LONG)
  // 	clause_pause = clause_pause * 32; // pause value is *320mS not *10mS

  // for (p = source; *p != 0; p++) {
  // 	if (!isspace2(*p))
  // 		break;
  // }
  // if (*p == 0) {
  // 	// No characters except spaces. This is not a sentence.
  // 	// Don't add this pause, just make up the previous pause to this value;
  // 	clause_pause -= max_clause_pause;
  // 	if (clause_pause < 0)
  // 		clause_pause = 0;

  // 	if (new_sentence)
  // 		terminator |= CLAUSE_TYPE_SENTENCE; // carry forward an end-of-sentence indicator
  // 	max_clause_pause += clause_pause;
  // 	new_sentence2 = false;
  // } else {
  // 	max_clause_pause = clause_pause;
  // 	new_sentence2 = new_sentence;
  // }
  // tr->clause_terminator = terminator;

  // if (new_sentence2) {
  // 	count_sentences++;
  // 	if (skip_sentences > 0) {
  // 		skip_sentences--;
  // 		if (skip_sentences == 0)
  // 			skipping_text = false;
  // 	}
  // }

  // MAKE_MEM_UNDEFINED(&ph_list2, sizeof(ph_list2));
  // memset(&ph_list2[0], 0, sizeof(ph_list2[0]));
  // ph_list2[0].phcode = phonPAUSE_SHORT;

  // n_ph_list2 = 1;
  // tr->prev_last_stress = 0;
  // tr->prepause_timeout = 0;
  // tr->expect_verb = 0;
  // tr->expect_noun = 0;
  // tr->expect_past = 0;
  // tr->expect_verb_s = 0;
  // tr->phonemes_repeat_count = 0;
  // tr->end_stressed_vowel = 0;
  // tr->prev_dict_flags[0] = 0;
  // tr->prev_dict_flags[1] = 0;

  // word_count = 0;
  // word_flags = 0;
  // next_word_flags = 0;

  // sbuf[0] = 0;
  // sbuf[1] = ' ';
  // sbuf[2] = ' ';
  // ix = 3;
  // prev_in = ' ';

  // words[0].start = ix;
  // words[0].flags = 0;

  // words[0].length = CalcWordLength(source_index, charix_top, charix, words, 0);

  // int prev_out2;
  // while (!finished && (ix < (int)sizeof(sbuf) - 1)) {
  // 	prev_out2 = prev_out;
  // 	utf8_in2(&prev_out, &sbuf[ix-1], 1);

  // 	if (tr->langopts.tone_numbers && IsDigit09(prev_out) && IsAlpha(prev_out2)) {
  // 		// tone numbers can be part of a word, consider them as alphabetic
  // 		prev_out = 'a';
  // 	}

  // 	if (prev_in_save != 0) {
  // 		prev_in = prev_in_save;
  // 		prev_in_save = 0;
  // 	} else if (source_index > 0)
  // 		utf8_in2(&prev_in, &source[source_index-1], 1);

  // 	unsigned int prev_source_index = source_index;

  // 	if (char_inserted) {
  // 		c = char_inserted;
  // 		char_inserted = 0;
  // 	} else {
  // 		source_index += utf8_in(&cc, &source[source_index]);
  // 		c = cc;
  // 	}

  // 	if (c == 0) {
  // 		finished = true;
  // 		c = ' ';
  // 		next_in = ' ';
  // 		next_in_nbytes = 0;
  // 	}
  // 	else
  // 		next_in_nbytes = utf8_in(&next_in, &source[source_index]);

  // 	if (c == CTRL_EMBEDDED) {
  // 		// start of embedded command in the text
  // 		int srcix = source_index-1;

  // 		if (prev_in != ' ') {
  // 			c = ' ';
  // 			prev_in_save = c;
  // 			source_index--;
  // 		} else {
  // 			embedded_count += EmbeddedCommand(&source_index);
  // 			prev_in_save = prev_in;
  // 			// replace the embedded command by spaces
  // 			memset(&source[srcix], ' ', source_index-srcix);
  // 			source_index = srcix;
  // 			continue;
  // 		}
  // 	}

  // 	if ((option_sayas2 == SAYAS_KEY) && (c != ' ')) {
  // 		if ((prev_in == ' ') && (next_in == ' '))
  // 			option_sayas2 = SAYAS_SINGLE_CHARS; // single character, speak its name
  // 		c = towlower2(c, tr);
  // 	}

  // 	if (phoneme_mode) {
  // 		all_upper_case = FLAG_PHONEMES;

  // 		if ((c == ']') && (next_in == ']')) {
  // 			phoneme_mode = false;
  // 			source_index++;
  // 			c = ' ';
  // 		}
  // 	} else if ((option_sayas2 & 0xf0) == SAYAS_DIGITS) {
  // 		if (iswdigit(c)) {
  // 			count_sayas_digits++;
  // 			if (count_sayas_digits > (option_sayas2 & 0xf)) {
  // 				// break after the specified number of digits
  // 				c = ' ';
  // 				space_inserted = true;
  // 				count_sayas_digits = 0;
  // 			}
  // 		} else {
  // 			count_sayas_digits = 0;
  // 			if (iswdigit(prev_out)) {
  // 				c = ' ';
  // 				space_inserted = true;
  // 			}
  // 		}
  // 	} else if ((option_sayas2 & 0x10) == 0) {
  // 		// speak as words

  // 		if ((c == 0x92) || (c == 0xb4) || (c == 0x2019) || (c == 0x2032))
  // 			c = '\''; // 'microsoft' quote or sexed closing single quote, or prime - possibly used as apostrophe

  // 		if (((c == 0x2018) || (c == '?')) && IsAlpha(prev_out) && IsAlpha(next_in)) {
  // 			// ? between two letters may be a smart-quote replaced by ?
  // 			c = '\'';
  // 		}

  // 		if (c == CHAR_EMPHASIS) {
  // 			// this character is a marker that the previous word is the focus of the clause
  // 			c = ' ';
  // 			word_flags |= FLAG_FOCUS;
  // 		}

  // 		if (c == CHAR_COMMA_BREAK) {
  // 			c = ' ';
  // 			word_flags |= FLAG_COMMA_AFTER;
  // 		}
  // 		// language specific character translations
  // 		c = TranslateChar(tr, &source[source_index], prev_in, c, next_in, &char_inserted, &word_flags);
  // 		if (c == 8)
  // 			continue; // ignore this character

  // 		if (char_inserted)
  // 			next_in = char_inserted;

  // 		// allow certain punctuation within a word (usually only apostrophe)
  // 		if (!IsAlpha(c) && !IsSpace(c) && (wcschr(tr->punct_within_word, c) == 0)) {
  // 			if (IsAlpha(prev_out)) {
  // 				if (tr->langopts.tone_numbers && IsDigit09(c) && !IsDigit09(next_in)) {
  // 					// allow a tone number as part of the word
  // 				} else {
  // 					c = ' '; // ensure we have an end-of-word terminator
  // 					space_inserted = true;
  // 				}
  // 			}
  // 		}

  // 		if (iswdigit(prev_out)) {
  // 			if (!iswdigit(c) && (c != '.') && (c != ',') && (c != ' ')) {
  // 				c = ' '; // terminate digit string with a space
  // 				space_inserted = true;
  // 			}
  // 		} else { // Prev output is not digit
  // 			if (prev_in == ',') {
  // 				// Workaround for several consecutive commas —
  // 				// replace current character with space
  // 				if (c == ',')
  // 					c = ' ';
  // 			} else {
  // 				decimal_sep_count = false;
  // 			}
  // 		}

  // 		if (c == '[') {
  // 			if ((next_in == '\002') || ((next_in == '[') && option_phoneme_input)) {
  // 				//  "[\002" is used internally to start phoneme mode
  // 				phoneme_mode = true;
  // 				source_index++;
  // 				continue;
  // 			}
  // 		}

  // 		if (IsAlpha(c)) {
  // 			alpha_count++;
  // 			if (!IsAlpha(prev_out) || (tr->langopts.ideographs && ((c > 0x3040) || (prev_out > 0x3040)))) {
  // 				if (wcschr(tr->punct_within_word, prev_out) == 0)
  // 					letter_count = 0; // don't reset count for an apostrophy within a word

  // 				if ((prev_out != ' ') && (wcschr(tr->punct_within_word, prev_out) == 0)) {
  // 					// start of word, insert space if not one there already
  // 					c = ' ';
  // 					space_inserted = true;

  // 					if (!IsBracket(prev_out)) // ?? perhaps only set FLAG_NOSPACE for . - /  (hyphenated words, URLs, etc)
  // 						next_word_flags |= FLAG_NOSPACE;
  // 				} else {
  // 					if (iswupper(c))
  // 						word_flags |= FLAG_FIRST_UPPER;

  // 					if ((prev_out == ' ') && iswdigit(sbuf[ix-2]) && !iswdigit(prev_in)) {
  // 						// word, following a number, but with a space between
  // 						// Add an extra space, to distinguish "2 a" from "2a"
  // 						sbuf[ix++] = ' ';
  // 						words[word_count].start++;
  // 					}
  // 				}
  // 			}

  // 			if (c != ' ') {
  // 				letter_count++;

  // 				if (tr->letter_bits_offset > 0) {
  // 					if (((c < 0x250) && (prev_out >= tr->letter_bits_offset)) ||
  // 					    ((c >= tr->letter_bits_offset) && (letter_count > 1) && (prev_out < 0x250))) {
  // 						// Don't mix native and Latin characters in the same word
  // 						// Break into separate words
  // 						if (IsAlpha(prev_out)) {
  // 							c = ' ';
  // 							space_inserted = true;
  // 							word_flags |= FLAG_HYPHEN_AFTER;
  // 							next_word_flags |= FLAG_HYPHEN;
  // 						}
  // 					}
  // 				}
  // 			}

  // 			if (iswupper(c)) {
  // 				c = towlower2(c, tr);

  // 				if (tr->langopts.param[LOPT_CAPS_IN_WORD]) {
  // 					if (syllable_marked == false) {
  // 						char_inserted = c;
  // 						c = 0x2c8; // stress marker
  // 						syllable_marked = true;
  // 					}
  // 				} else {
  // 					if (iswlower(prev_in)) {
  // 						// lower case followed by upper case, possibly CamelCase
  // 						if (UpperCaseInWord(tr, &sbuf[ix], c) == 0) { // start a new word
  // 							c = ' ';
  // 							space_inserted = true;
  // 							prev_in_save = c;
  // 						}
  // 					} else if ((c != ' ') && iswupper(prev_in) && iswlower(next_in)) {
  // 						int next2_in;
  // 						utf8_in(&next2_in, &source[source_index + next_in_nbytes]);

  // 						if ((tr->translator_name == L('n', 'l')) && (letter_count == 2) && (c == 'j') && (prev_in == 'I')) {
  // 							// Dutch words may capitalise initial IJ, don't split
  // 						} else if (IsAlpha(next2_in)) {
  // 							// changing from upper to lower case, start new word at the last uppercase, if 3 or more letters
  // 							c = ' ';
  // 							space_inserted = true;
  // 							prev_in_save = c;
  // 							next_word_flags |= FLAG_NOSPACE;
  // 						}
  // 					}
  // 				}
  // 			} else {
  // 				if ((all_upper_case) && (letter_count > 2)) {
  // 					// Flag as plural only English
  // 					if (tr->translator_name == L('e', 'n') && (c == 's') && (next_in == ' ')) {
  // 						c = ' ';
  // 						all_upper_case |= FLAG_HAS_PLURAL;

  // 						if (sbuf[ix-1] == '\'')
  // 							sbuf[ix-1] = ' ';
  // 					} else
  // 						all_upper_case = 0; // current word contains lower case letters, not "'s"
  // 				} else
  // 					all_upper_case = 0;
  // 			}
  // 		} else if (c == '-') {
  // 			if (!IsSpace(prev_in) && IsAlpha(next_in)) {
  // 				if (prev_out != ' ') {
  // 					// previous 'word' not yet ended (not alpha or numeric), start new word now.
  // 					c = ' ';
  // 					space_inserted = true;
  // 				} else {
  // 					// '-' between two letters is a hyphen, treat as a space
  // 					word_flags |= FLAG_HYPHEN;
  // 					if (word_count > 0)
  // 						words[word_count-1].flags |= FLAG_HYPHEN_AFTER;
  // 					c = ' ';
  // 				}
  // 			} else if ((prev_in == ' ') && (next_in == ' ')) {
  // 				// ' - ' dash between two spaces, treat as pause
  // 				c = ' ';
  // 				pre_pause_add = 4;
  // 			} else if (next_in == '-') {
  // 				// double hyphen, treat as pause
  // 				source_index++;
  // 				c = ' ';
  // 				pre_pause_add = 4;
  // 			} else if ((prev_out == ' ') && IsAlpha(prev_out2) && !IsAlpha(prev_in)) {
  // 				// insert extra space between a word + space + hyphen, to distinguish 'a -2' from 'a-2'
  // 				sbuf[ix++] = ' ';
  // 				words[word_count].start++;
  // 			}
  // 		} else if (c == '.') {
  // 			if (prev_out == '.') {
  // 				// multiple dots, separate by spaces. Note >3 dots has been replaced by elipsis
  // 				c = ' ';
  // 				space_inserted = true;
  // 			} else if ((word_count > 0) && !(words[word_count-1].flags & FLAG_NOSPACE) && IsAlpha(prev_in)) {
  // 				// dot after a word, with space following, probably an abbreviation
  // 				words[word_count-1].flags |= FLAG_HAS_DOT;

  // 				if (IsSpace(next_in) || (next_in == '-'))
  // 					c = ' '; // remove the dot if it's followed by a space or hyphen, so that it's not pronounced
  // 			}
  // 		} else if (c == '\'') {
  // 			if (((prev_in == '.' && next_in == 's') || iswalnum(prev_in)) && IsAlpha(next_in)) {
  // 				// between two letters, or in an abbreviation (eg. u.s.a.'s). Consider the apostrophe as part of the word
  // 				single_quoted = false;
  // 			} else if ((tr->langopts.param[LOPT_APOSTROPHE] & 1) && IsAlpha(next_in))
  // 				single_quoted = false; // apostrophe at start of word is part of the word
  // 			else if ((tr->langopts.param[LOPT_APOSTROPHE] & 2) && IsAlpha(prev_in))
  // 				single_quoted = false; // apostrophe at end of word is part of the word
  // 			else if ((wcschr(tr->char_plus_apostrophe, prev_in) != 0) && (prev_out2 == ' ')) {
  // 				// consider single character plus apostrophe as a word
  // 				single_quoted = false;
  // 				if (next_in == ' ')
  // 					source_index++; // skip following space
  // 			} else {
  // 				if ((prev_out == 's') && (single_quoted == false)) {
  // 					// looks like apostrophe after an 's'
  // 					c = ' ';
  // 				} else {
  // 					if (IsSpace(prev_out))
  // 						single_quoted = true;
  // 					else
  // 						single_quoted = false;

  // 					pre_pause_add = 4; // single quote
  // 					c = ' ';
  // 				}
  // 			}
  // 		} else if (lookupwchar(breaks, c) != 0)
  // 			c = ' '; // various characters to treat as space
  // 		else if (iswdigit(c)) {
  // 			if (tr->langopts.tone_numbers && IsAlpha(prev_out) && !IsDigit(next_in)) {
  // 			} else if ((prev_out != ' ') && !iswdigit(prev_out)) {
  // 				if ((prev_out != tr->langopts.decimal_sep) || ((decimal_sep_count == true) && (tr->langopts.decimal_sep == ','))) {
  // 					c = ' ';
  // 					space_inserted = true;
  // 				} else
  // 					decimal_sep_count = true;
  // 			} else if ((prev_out == ' ') && IsAlpha(prev_out2) && !IsAlpha(prev_in)) {
  // 				// insert extra space between a word and a number, to distinguish 'a 2' from 'a2'
  // 				sbuf[ix++] = ' ';
  // 				words[word_count].start++;
  // 			}
  // 		}
  // 	}

  // 	if (IsSpace(c)) {
  // 		if (prev_out == ' ') {
  // 			word_flags |= FLAG_MULTIPLE_SPACES;
  // 			continue; // multiple spaces
  // 		}

  // 		if ((cc == 0x09) || (cc == 0x0a))
  // 			next_word_flags |= FLAG_MULTIPLE_SPACES; // tab or newline, not a simple space

  // 		if (space_inserted) {
  // 			// count the number of characters since the start of the word
  // 			j = 0;
  // 			k = source_index - 1;
  // 			while ((k >= source_index_word) && (charix[k] != 0)) {
  // 				if (charix[k] > 0) // don't count initial bytes of multi-byte character
  // 					j++;
  // 				k--;
  // 			}
  // 			words[word_count].length = j;
  // 		}

  // 		source_index_word = source_index;

  // 		// end of 'word'
  // 		sbuf[ix++] = ' ';

  // 		if ((word_count < N_CLAUSE_WORDS-1) && (ix > words[word_count].start)) {
  // 			if (embedded_count > 0) {
  // 				// there are embedded commands before this word
  // 				embedded_list[embedded_ix-1] |= 0x80; // terminate list of commands for this word
  // 				words[word_count].flags |= FLAG_EMBEDDED;
  // 				embedded_count = 0;
  // 			}
  // 			if (alpha_count == 0) {
  // 				all_upper_case &= ~FLAG_ALL_UPPER;
  // 			}
  // 			words[word_count].pre_pause = pre_pause;
  // 			words[word_count].flags |= (all_upper_case | word_flags | word_emphasis);

  // 			if (pre_pause > 0) {
  // 				// insert an extra space before the word, to prevent influence from previous word across the pause
  // 				for (j = ix; j > words[word_count].start; j--)
  // 					sbuf[j] = sbuf[j-1];
  // 				sbuf[j] = ' ';
  // 				words[word_count].start++;
  // 				ix++;
  // 			}

  // 			word_count++;
  // 			words[word_count].start = ix;
  // 			words[word_count].flags = 0;

  // 			words[word_count].length = CalcWordLength(source_index, charix_top, charix, words, word_count);

  // 			word_flags = next_word_flags;
  // 			next_word_flags = 0;
  // 			pre_pause = 0;
  // 			all_upper_case = FLAG_ALL_UPPER;
  // 			alpha_count = 0;
  // 			syllable_marked = false;
  // 		}

  // 		if (space_inserted) {
  // 			source_index = prev_source_index; // rewind to the previous character
  // 			char_inserted = 0;
  // 			space_inserted = false;
  // 		}
  // 	} else {
  // 		if ((ix < (N_TR_SOURCE - 4)))
  // 			ix += utf8_out(c, &sbuf[ix]);
  // 	}
  // 	if (pre_pause_add > pre_pause)
  // 		pre_pause = pre_pause_add;
  // 	pre_pause_add = 0;
  // }

  // if ((word_count == 0) && (embedded_count > 0)) {
  // 	// add a null 'word' to carry the embedded command flag
  // 	embedded_list[embedded_ix-1] |= 0x80;
  // 	words[word_count].flags |= FLAG_EMBEDDED;
  // 	word_count = 1;
  // }

  // tr->clause_end = &sbuf[ix-1];
  // sbuf[ix] = 0;
  // words[0].pre_pause = 0; // don't add extra pause at beginning of clause
  // words[word_count].pre_pause = 8;
  // if (word_count > 0) {
  // 	ix = word_count-1;
  // 	while ((ix > 0) && (IsBracket(sbuf[words[ix].start])))
  // 		ix--; // the last word is a bracket, mark the previous word as last
  // 	words[ix].flags |= FLAG_LAST_WORD;

  // 	// FLAG_NOSPACE check to avoid recognizing  .mr  -mr
  // 	if ((terminator & CLAUSE_DOT_AFTER_LAST_WORD) && !(words[word_count-1].flags & FLAG_NOSPACE))
  // 		words[word_count-1].flags |= FLAG_HAS_DOT;
  // }
  // words[0].flags |= FLAG_FIRST_WORD;

  // // Each TranslateWord2 may require up to 7 phonemes
  // // and after this loop we require 2 phonemes
  // for (ix = 0; ix < word_count && (n_ph_list2 < N_PHONEME_LIST-7-2); ix++) {
  // 	int nx;
  // 	int c_temp;
  // 	char *pn;
  // 	char *pw;
  // 	char number_buf[150];
  // 	WORD_TAB num_wtab[50]; // copy of 'words', when splitting numbers into parts

  // 	// start speaking at a specified word position in the text?
  // 	count_words++;
  // 	if (skip_words > 0) {
  // 		skip_words--;
  // 		if (skip_words == 0)
  // 			skipping_text = false;
  // 	}
  // 	if (skipping_text)
  // 		continue;

  // 	current_alphabet = NULL;

  // 	// digits should have been converted to Latin alphabet ('0' to '9')
  // 	word = pw = &sbuf[words[ix].start];

  // 	if (iswdigit(word[0]) && (tr->langopts.break_numbers != BREAK_THOUSANDS)) {
  // 		// Languages with 100000 numbers.  Remove thousands separators so that we can insert them again later
  // 		pn = number_buf;
  // 		while (pn < &number_buf[sizeof(number_buf)-20]) {
  // 			if (iswdigit(*pw))
  // 				*pn++ = *pw++;
  // 			else if ((*pw == tr->langopts.thousands_sep) && (pw[1] == ' ')
  // 			           && iswdigit(pw[2]) && (pw[3] != ' ') && (pw[4] != ' ')) { // don't allow only 1 or 2 digits in the final part
  // 				pw += 2;
  // 				ix++; // skip "word"
  // 			} else {
  // 				nx = pw - word;
  // 				memset(word, ' ', nx);
  // 				nx = pn - number_buf;
  // 				memcpy(word, number_buf, nx);
  // 				break;
  // 			}
  // 		}
  // 		pw = word;
  // 	}

  // 	for (n_digits = 0; iswdigit(word[n_digits]); n_digits++) // count consecutive digits
  // 		;

  // 	if (n_digits > 4 && n_digits <= 32) {
  // 		// word is entirely digits, insert commas and break into 3 digit "words"
  // 		int nw = 0;

  // 		number_buf[0] = ' ';
  // 		number_buf[1] = ' ';
  // 		number_buf[2] = ' ';
  // 		pn = &number_buf[3];
  // 		nx = n_digits;

  // 		if ((n_digits > tr->langopts.max_digits) || (word[0] == '0'))
  // 			words[ix].flags |= FLAG_INDIVIDUAL_DIGITS;

  // 		while (pn < &number_buf[sizeof(number_buf)-20]) {
  // 			if (!IsDigit09(c = *pw++) && (c != tr->langopts.decimal_sep))
  // 				break;

  // 			*pn++ = c;
  // 			nx--;
  // 			if ((nx > 0) && (tr->langopts.break_numbers & (1U << nx))) {
  // 				memcpy(&num_wtab[nw++], &words[ix], sizeof(WORD_TAB)); // copy the 'words' entry for each word of numbers

  // 				if (tr->langopts.thousands_sep != ' ')
  // 					*pn++ = tr->langopts.thousands_sep;
  // 				*pn++ = ' ';

  // 				if ((words[ix].flags & FLAG_INDIVIDUAL_DIGITS) == 0) {
  // 					if (tr->langopts.break_numbers & (1 << (nx-1))) {
  // 						// the next group only has 1 digits, make it three
  // 						*pn++ = '0';
  // 						*pn++ = '0';
  // 					}
  // 					if (tr->langopts.break_numbers & (1 << (nx-2))) {
  // 						// the next group only has 2 digits (eg. Indian languages), make it three
  // 						*pn++ = '0';
  // 					}
  // 				}
  // 			}
  // 		}
  // 		pw--;
  // 		memcpy(&num_wtab[nw], &words[ix], sizeof(WORD_TAB)*2); // the original number word, and the word after it

  // 		for (j = 1; j <= nw; j++)
  // 			num_wtab[j].flags &= ~(FLAG_MULTIPLE_SPACES | FLAG_EMBEDDED); // don't use these flags for subsequent parts when splitting a number

  // 		// include the next few characters, in case there are an ordinal indicator or other suffix
  // 		memcpy(pn, pw, 16);
  // 		pn[16] = 0;
  // 		nw = 0;

  // 		for (pw = &number_buf[3]; pw < pn;) {
  // 			// keep wflags for each part, for FLAG_HYPHEN_AFTER
  // 			dict_flags = TranslateWord2(tr, pw, &num_wtab[nw++], words[ix].pre_pause);
  // 			while (*pw++ != ' ')
  // 				;
  // 			words[ix].pre_pause = 0;
  // 		}
  // 	} else {
  // 		pre_pause = 0;

  // 		dict_flags = TranslateWord2(tr, word, &words[ix], words[ix].pre_pause);

  // 		if (pre_pause > words[ix+1].pre_pause) {
  // 			words[ix+1].pre_pause = pre_pause;
  // 			pre_pause = 0;
  // 		}

  // 		if (dict_flags & FLAG_SPELLWORD) {
  // 			// redo the word, speaking single letters
  // 			for (pw = word; *pw != ' ';) {
  // 				memset(number_buf, ' ', 9);
  // 				nx = utf8_in(&c_temp, pw);
  // 				memcpy(&number_buf[2], pw, nx);
  // 				TranslateWord2(tr, &number_buf[2], &words[ix], 0);
  // 				pw += nx;
  // 			}
  // 		}

  // 		if ((dict_flags & (FLAG_ALLOW_DOT | FLAG_NEEDS_DOT)) && (ix == word_count - 1 - dictionary_skipwords) && (terminator & CLAUSE_DOT_AFTER_LAST_WORD)) {
  // 			// probably an abbreviation such as Mr. or B. rather than end of sentence
  // 			clause_pause = 10;
  // 			if (tone_out != NULL)
  // 				*tone_out = 4;
  // 		}
  // 	}

  // 	if (dict_flags & FLAG_SKIPWORDS) {
  // 		// dictionary indicates skip next word(s)
  // 		while (dictionary_skipwords > 0) {
  // 			words[ix+dictionary_skipwords].flags |= FLAG_DELETE_WORD;
  // 			dictionary_skipwords--;
  // 		}
  // 	}
  // }

  // if (embedded_read < embedded_ix) {
  // 	// any embedded commands not yet processed?
  // 	Word_EmbeddedCmd();
  // }

  // for (ix = 0; ix < 2; ix++) {
  // 	// terminate the clause with 2 PAUSE phonemes
  // 	PHONEME_LIST2 *p2;
  // 	p2 = &ph_list2[n_ph_list2 + ix];
  // 	p2->phcode = phonPAUSE;
  // 	p2->stresslevel = 0;
  // 	p2->sourceix = source_index;
  // 	p2->synthflags = 0;
  // }
  // n_ph_list2 += 2;

  // if (Eof() && ((word_count == 0) || (option_endpause == 0)))
  // 	clause_pause = 10;

  // MakePhonemeList(tr, clause_pause, new_sentence2);
  // phoneme_list[N_PHONEME_LIST].ph = NULL; // recognize end of phoneme_list array, in Generate()
  // phoneme_list[N_PHONEME_LIST].sourceix = 1;

  // if (embedded_count) { // ???? is this needed
  // 	phoneme_list[n_phoneme_list-2].synthflags = SFLAG_EMBEDDED;
  // 	embedded_list[embedded_ix-1] |= 0x80;
  // 	embedded_list[embedded_ix] = 0x80;
  // }

  // new_sentence = false;
  // if (terminator & CLAUSE_TYPE_SENTENCE)
  // 	new_sentence = true; // next clause is a new sentence

  // if (voice_change != NULL) {
  // 	// return new voice name if an embedded voice change command terminated the clause
  // 	if (terminator & CLAUSE_TYPE_VOICE_CHANGE)
  // 		*voice_change = voice_change_name;
  // 	else
  // 		*voice_change = NULL;
  // }
  return TranslateClauseResult(tone: 0, terminator: 0);
}
