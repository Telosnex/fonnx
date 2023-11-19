// ignore_for_file: non_constant_identifier_names

import 'package:fonnx/piper/phonemizer/encoding_c.dart';
import 'package:fonnx/piper/phonemizer/encoding_h.dart';
import 'package:fonnx/piper/phonemizer/translate_c.dart';
import 'package:fonnx/piper/phonemizer/translate_h.dart';

EspeakNgTextDecoder? p_decoder;

int countCharacters = 0;

const  N_XML_BUF =  500;
const N_XML_BUF2 = 20;
	 String ungot_string =  List<String>.filled(N_XML_BUF2 + 4, ' ').join('');
int ungot_string_ix = -1;
bool clear_skipping_text = false;
int ungot_char2 = 0;
int ungot_char = 0;

bool Eof() {
	if (ungot_char != 0) {
return false;
  }
	
	return text_decoder_eof(p_decoder!);
}

 int GetC()
{
	int c1;

	if ((c1 = ungot_char) != 0) {
		ungot_char = 0;
		return c1;
	}

	countCharacters++;
	return text_decoder_getc(p_decoder!);
}


int ReadClause(Translator tr)
{
   int resultToneType = 0;

    int resultCharixTop = 0;
    int resultCharix = 0;
    String resultBuf = '';
    String resultVoiceChange = '';
	/* Find the end of the current clause.
	    Write the clause into  buf

	    returns: clause type (bits 0-7: pause x10mS, bits 8-11 intonation type)

	    Also checks for blank line (paragraph) as end-of-clause indicator.

	    Does not end clause for:
	        punctuation immediately followed by alphanumeric  eg.  1.23  !Speak  :path
	        repeated punctuation, eg.   ...   !!!
	 */

	String c1 = ' '; // current character
	int c2; // next character
	String cprev = ' '; // previous character
	int c_next;
	int parag;
	int ix = 0;
	int j;
	int nl_count;
	int linelength = 0;
	int phoneme_mode = 0;
	int n_xml_buf;
	int terminator;
	bool any_alnum = false;
	int punct_data = 0;
	bool is_end_clause;
	int announced_punctuation = 0;
	bool stressed_word = false;
	int end_clause_after_tag = 0;
	int end_clause_index = 0;
  final String xml_buf =  List<String>.filled(N_XML_BUF + 1, ' ').join('');
   // for &<name> and &<number> sequences
  final String xml_buf2 =  List<String>.filled(N_XML_BUF2 + 2, ' ').join('');


	// static char ungot_string[N_XML_BUF2+4];
	// static int ungot_string_ix = -1;

	if (clear_skipping_text) {
		skippingText = false;
		clear_skipping_text = false;
	}
  tr.phonemesRepeatCount = 0;
  tr.clauseUpperCount = 0;
  tr.clauseLowerCount = 0;

	resultToneType = 0;
	resultVoiceChange = '';

	if (ungot_char2 != 0) {
		c2 = ungot_char2;
	} else if (Eof()) {
		c2 = 0;
	} else {
		c2 = GetC();
	}

	while (!Eof() || (ungot_char != 0) || (ungot_char2 != 0) || (ungot_string_ix >= 0)) {
		if (!iswalnum(c1)) {
			if ((end_character_position > 0) && (count_characters > end_character_position)) {
				return CLAUSE_EOF;
			}

			if ((skip_characters > 0) && (count_characters >= skip_characters)) {
				// reached the specified start position
				// don't break a word
				clear_skipping_text = true;
				skip_characters = 0;
				UngetC(c2);
				return CLAUSE_NONE;
			}
		}
		int cprev2 = cprev;
		cprev = c1;
		c1 = c2;

		if (ungot_string_ix >= 0) {
			if (ungot_string[ungot_string_ix] == 0) {
				MAKE_MEM_UNDEFINED(&ungot_string, sizeof(ungot_string));
				ungot_string_ix = -1;
			}
		}

		if ((ungot_string_ix == 0) && (ungot_char2 == 0))
			c1 = ungot_string[ungot_string_ix++];
		if (ungot_string_ix >= 0) {
			c2 = ungot_string[ungot_string_ix++];
		} else if (Eof()) {
			c2 = ' ';
		} else {
			c2 = GetC();
		}

		ungot_char2 = 0;

		if ((option_ssml) && (phoneme_mode == 0)) {
			if ((c1 == '&') && ((c2 == '#') || ((c2 >= 'a') && (c2 <= 'z')))) {
				n_xml_buf = 0;
				c1 = c2;
				while (!Eof() && (iswalnum(c1) || (c1 == '#')) && (n_xml_buf < N_XML_BUF2)) {
					xml_buf2[n_xml_buf++] = c1;
					c1 = GetC();
				}
				xml_buf2[n_xml_buf] = 0;
				if (Eof()) {
					c2 = '\0';
				} else {
					c2 = GetC();
				}
				sprintf(ungot_string, "%s%c%c", &xml_buf2[0], c1, c2);

				int found = -1;
				if (c1 == ';') {
					found = ParseSsmlReference(xml_buf2, &c1, &c2);
				}

				if (found <= 0) {
					ungot_string_ix = 0;
					c1 = '&';
					c2 = ' ';
				}

				if ((c1 <= 0x20) && ((sayas_mode == SAYAS_SINGLE_CHARS) || (sayas_mode == SAYAS_KEY)))
					c1 += 0xe000; // move into unicode private usage area
			} else if (c1 == '<') {
				if ((c2 == '/') || iswalpha(c2) || c2 == '!' || c2 == '?') {
					// check for space in the output buffer for embedded commands produced by the SSML tag
					if (ix > (n_buf - 20)) {
						// Perhaps not enough room, end the clause before the SSML tag
						ungot_char2 = c1;
						TerminateBufWithSpaceAndZero(buf, ix, &c2);
						return CLAUSE_NONE;
					}

					// SSML Tag
					n_xml_buf = 0;
					c1 = c2;
					while (!Eof() && (c1 != '>') && (n_xml_buf < N_XML_BUF)) {
						xml_buf[n_xml_buf++] = c1;
						c1 = GetC();
					}
					xml_buf[n_xml_buf] = 0;
					c2 = ' ';

					terminator = ProcessSsmlTag(xml_buf, buf, &ix, n_buf, xmlbase, &audio_text, current_voice_id, &base_voice, base_voice_variant_name, &ignore_text, &clear_skipping_text, &sayas_mode, &sayas_start, ssml_stack, &n_ssml_stack, &n_param_stack, (int *)speech_parameters);

					if (terminator != 0) {
						TerminateBufWithSpaceAndZero(buf, ix, NULL);

						if (terminator & CLAUSE_TYPE_VOICE_CHANGE)
							strcpy(voice_change, current_voice_id);
						return terminator;
					}
					c1 = ' ';
					if (!Eof()) {
						c2 = GetC();
					}
					continue;
				}
			}
		}

		if (ignore_text)
			continue;

		if ((c2 == '\n') && (option_linelength == -1)) {
			// single-line mode, return immediately on NL
			if ((terminator = clause_type_from_codepoint(c1)) == CLAUSE_NONE) {
				charix[ix] = count_characters - clause_start_char;
				*charix_top = ix;
				ix += utf8_out(c1, &buf[ix]);
				terminator = CLAUSE_PERIOD; // line doesn't end in punctuation, assume period
			}
			TerminateBufWithSpaceAndZero(buf, ix, NULL);
			return terminator;
		}

		if (c1 == CTRL_EMBEDDED) {
 			// an embedded command. If it's a voice change, end the clause
			if (c2 == 'V') {
				buf[ix++] = 0; // end the clause at this point
				while (!Eof() && !iswspace(c1 = GetC()) && (ix < (n_buf-1)))
					buf[ix++] = c1; // add voice name to end of buffer, after the text
				buf[ix++] = 0;
				return CLAUSE_VOICE;
			} else if (c2 == 'B') {
				// set the punctuation option from an embedded command
				//  B0     B1     B<punct list><space>
				strcpy(&buf[ix], "   ");
				ix += 3;

				if (!Eof() && (c2 = GetC()) == '0')
					option_punctuation = 0;
				else {
					option_punctuation = 1;
					option_punctlist[0] = 0;
					if (c2 != '1') {
						// a list of punctuation characters to be spoken, terminated by space
						j = 0;
						while (!Eof() && !iswspace(c2)) {
							option_punctlist[j++] = c2;
							c2 = GetC();
							buf[ix++] = ' ';
						}
						option_punctlist[j] = 0; // terminate punctuation list
						option_punctuation = 2;
					}
				}
				if (!Eof())
					c2 = GetC();
				continue;
			}
		}

		linelength++;

		 if (IgnoreOrReplaceChar(tr, &c1) == true)
		    continue;


		if (iswalnum(c1))
			any_alnum = true;
		else {
			if (stressed_word) {
				stressed_word = false;
				c1 = CHAR_EMPHASIS; // indicate this word is stressed
				UngetC(c2);
				c2 = ' ';
			}

			if (c1 == 0xf0b)
				c1 = ' '; // Tibet inter-syllabic mark, ?? replace by space ??

			if (c1 == 0xd4d) {
				// Malayalam virama, check if next character is Zero-width-joiner
				if (c2 == 0x200d)
					c1 = 0xd4e; // use this unofficial code for chillu-virama
			}
		}

		if (iswupper(c1)) {
			tr->clause_upper_count++;

			if ((option_capitals == 2) && (sayas_mode == 0) && !iswupper(cprev)) {
				char text_buf[30];
				if (LookupSpecial(tr, "_cap", text_buf) != NULL) {
					j = strlen(text_buf);
					if ((ix + j) < n_buf) {
						strcpy(&buf[ix], text_buf);
						ix += j;
					}
				}
			}
		} else if (iswalpha(c1))
			tr->clause_lower_count++;

		phoneme_mode = CheckPhonemeMode(option_phoneme_input, phoneme_mode, c1, c2);

		if (c1 == '\n') {
			parag = 0;

			// count consecutive newlines, ignoring other spaces
			while (!Eof() && iswspace(c2)) {
				if (c2 == '\n')
					parag++;
				c2 = GetC();
			}
			if (parag > 0) {
				// 2nd newline, assume paragraph
				if (end_clause_after_tag)
					RemoveChar(&buf[end_clause_index]); // delete clause-end punctiation
				TerminateBufWithSpaceAndZero(buf, ix, &c2);
				if (parag > 3)
					parag = 3;
				if (option_ssml) parag = 1;
				return (CLAUSE_PARAGRAPH-30) + 30*parag; // several blank lines, longer pause
			}

			if (linelength <= option_linelength) {
				// treat lines shorter than a specified length as end-of-clause
				TerminateBufWithSpaceAndZero(buf, ix, &c2);
				return CLAUSE_COLON;
			}

			linelength = 0;
		}

		announced_punctuation = 0;

		if ((phoneme_mode == 0) && (sayas_mode == 0)) {
			is_end_clause = false;

			if (end_clause_after_tag) {
				// Because of an xml tag, we are waiting for the
				// next non-blank character to decide whether to end the clause
				// i.e. is dot followed by an upper-case letter?

				if (!iswspace(c1)) {
					if (!IsAlpha(c1) || !iswlower(c1)) {
						ungot_char2 = c1;
						TerminateBufWithSpaceAndZero(buf, end_clause_index, &c2);
						return end_clause_after_tag;
					}
					end_clause_after_tag = 0;
				}
			}

			if ((c1 == '.') && (c2 == '.')) {
				while (!Eof() && (c_next = GetC()) == '.') {
					// 3 or more dots, replace by elipsis
					c1 = 0x2026;
					c2 = ' ';
				}
				if (c1 == 0x2026)
					c2 = c_next;
				else
					UngetC(c_next);
			}

			punct_data = 0;
			if ((punct_data = clause_type_from_codepoint(c1)) != CLAUSE_NONE) {

				// Handling of sequences of ? and ! like ??!?, !!??!, ?!! etc
				// Use only first char as determinant
				if(punct_data & (CLAUSE_QUESTION | CLAUSE_EXCLAMATION)) {
					while(!Eof() && clause_type_from_codepoint(c2) & (CLAUSE_QUESTION | CLAUSE_EXCLAMATION)) {
						c_next = GetC();
						c2 = c_next;
					}
				}

				if (punct_data & CLAUSE_PUNCTUATION_IN_WORD) {
					// Armenian punctuation inside a word
					stressed_word = true;
					*tone_type = punct_data >> 12 & 0xf; // override the end-of-sentence type
					continue;
				}

				if (iswspace(c2) || (punct_data & CLAUSE_OPTIONAL_SPACE_AFTER) || IsBracket(c2) || (c2 == '?') || Eof() || c2 == CTRL_EMBEDDED) { // don't check for '-' because it prevents recognizing ':-)'
					// note: (c2='?') is for when a smart-quote has been replaced by '?'
					is_end_clause = true;
				}
			}

			// don't announce punctuation for the alternative text inside inside <audio> ... </audio>
			if (c1 == 0xe000+'<')  c1 = '<';
			if (option_punctuation && iswpunct(c1) && (audio_text == false)) {
				// option is set to explicitly speak punctuation characters
				// if a list of allowed punctuation has been set up, check whether the character is in it
				if ((option_punctuation == 1) || (wcschr(option_punctlist, c1) != NULL)) {
					tr->phonemes_repeat_count = 0;
					if ((terminator = AnnouncePunctuation(tr, c1, &c2, buf, &ix, is_end_clause)) >= 0)
						return terminator;
					announced_punctuation = c1;
				}
			}

			if ((punct_data & CLAUSE_SPEAK_PUNCTUATION_NAME) && (announced_punctuation == 0)) {
				// used for elipsis (and 3 dots) if a pronunciation for elipsis is given in *_list
				char *p2;

				p2 = &buf[ix];
				char cn_buf[60];
				sprintf(p2, "%s", LookupCharName(cn_buf, tr, c1, true));
				if (p2[0] != 0) {
					ix += strlen(p2);
					announced_punctuation = c1;
					punct_data = punct_data & ~CLAUSE_INTONATION_TYPE; // change intonation type to 0 (full-stop)
				}
			}

			if (is_end_clause) {
				nl_count = 0;
				c_next = c2;

				if (iswspace(c_next)) {
					while (!Eof() && iswspace(c_next)) {
						if (c_next == '\n')
							nl_count++;
						c_next = GetC(); // skip past space(s)
					}
				}

				if ((c1 == '.') && (nl_count < 2))
					punct_data |= CLAUSE_DOT_AFTER_LAST_WORD;

				if (nl_count == 0) {
					if ((c1 == ',') && (cprev == '.') && (tr->translator_name == L('h', 'u')) && iswdigit(cprev2) && (iswdigit(c_next) || (iswlower(c_next)))) {
						// lang=hu, fix for ordinal numbers, eg:  "december 2., szerda", ignore ',' after ordinal number
						c1 = CHAR_COMMA_BREAK;
						is_end_clause = false;
					}

					if (c1 == '.' && c_next == '\'' && text_decoder_peekc(p_decoder) == 's') {
					 	// A special case to handle english acronym + genitive, eg. u.s.a.'s
						// But avoid breaking clause handling if anything else follows the apostrophe.
						is_end_clause = false;
					}

					if (c1 == '.') {
						if ((tr->langopts.numbers & NUM_ORDINAL_DOT) &&
						    (iswdigit(cprev) || (IsRomanU(cprev) && (IsRomanU(cprev2) || iswspace(cprev2))))) { // lang=hu
							// dot after a number indicates an ordinal number
							if (!iswdigit(cprev))
								is_end_clause = false; // Roman number followed by dot
							else if (iswlower(c_next) || (c_next == '-')) // hyphen is needed for lang-hu (eg. 2.-kal)
								is_end_clause = false; // only if followed by lower-case, (or if there is a XML tag)
						} 
						if (iswlower(c_next) && tr->langopts.lowercase_sentence == false) {
							// next word has no capital letter, this dot is probably from an abbreviation
							is_end_clause = false;
						}
						if (any_alnum == false) {
							// no letters or digits yet, so probably not a sentence terminator
							// Here, dot is followed by space or bracket
							c1 = ' ';
							is_end_clause = false;
						}
					} else {
						if (any_alnum == false) {
							// no letters or digits yet, so probably not a sentence terminator
							is_end_clause = false;
						}
					}

					if (is_end_clause && (c1 == '.') && (c_next == '<') && option_ssml) {
						// wait until after the end of the xml tag, then look for upper-case letter
						is_end_clause = false;
						end_clause_index = ix;
						end_clause_after_tag = punct_data;
					}
				}

				if (is_end_clause) {
					TerminateBufWithSpaceAndZero(buf, ix, &c_next);

					if (iswdigit(cprev) && !IsAlpha(c_next)) // ????
						punct_data &= ~CLAUSE_DOT_AFTER_LAST_WORD;
					if (nl_count > 1) {
						if ((punct_data == CLAUSE_QUESTION) || (punct_data == CLAUSE_EXCLAMATION))
							return punct_data + 35; // with a longer pause
						return CLAUSE_PARAGRAPH;
					}
					return punct_data; // only recognise punctuation if followed by a blank or bracket/quote
				} else if (!Eof()) {
					if (iswspace(c2))
						UngetC(c_next);
				}
			}
		}

		if (speech_parameters[espeakSILENCE] == 1)
			continue;

		if (c1 == announced_punctuation) {
			// This character has already been announced, so delete it so that it isn't spoken a second time.
			// Unless it's a hyphen or apostrophe (which is used by TranslateClause() )
			if (IsBracket(c1))
				c1 = 0xe000 + '('; // Unicode private useage area.  So TranslateRules() knows the bracket name has been spoken
			else if (c1 != '-')
				c1 = ' ';
		}

		j = ix+1;

		if (c1 == 0xe000 + '<') c1 = '<';

		ix += utf8_out(c1, &buf[ix]);
		if (!iswspace(c1) && !IsBracket(c1)) {
			charix[ix] = count_characters - clause_start_char;
			while (j < ix)
				charix[j++] = -1; // subsequent bytes of a multibyte character
		}
		*charix_top = ix;

		if (((ix > (n_buf-75)) && !IsAlpha(c1) && !iswdigit(c1))  ||  (ix >= (n_buf-4))) {
			// clause too long, getting near end of buffer, so break here
			// try to break at a word boundary (unless we actually reach the end of buffer).
			// (n_buf-4) is to allow for 3 bytes of multibyte character plus terminator.
			TerminateBufWithSpaceAndZero(buf, ix, &c2);
			return CLAUSE_NONE;
		}
	}

	if (stressed_word)
		ix += utf8_out(CHAR_EMPHASIS, &buf[ix]);
	if (end_clause_after_tag)
		RemoveChar(&buf[end_clause_index]); // delete clause-end punctiation
	TerminateBufWithSpaceAndZero(buf, ix, NULL);
	return CLAUSE_EOF; // end of file
}