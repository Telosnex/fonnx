enum EspeakChars {
  auto, /* 0 */
  utf8, /* 1 */
  bits8, /* 2 */
  wchar, /* 3 */
  bits16, /* 4 */
}

enum EspeakAudioOutput {
  /// PLAYBACK mode: Plays the audio data and supplies events to the calling program.
  playback,

  /// RETRIEVAL mode: Supplies audio data and events to the calling program without playing the sound.
  retrieval,

  /// SYNCHRONOUS mode: Acts like RETRIEVAL but does not return until synthesis is completed.
  synchronous,

  /// Synchronous playback: Plays back the audio and ensures that the calling program
  /// remains synchronized with the audio playback.
  synchPlayback
}

enum Gender {
  none,
  male,
  female,
}

// Dart class to represent the espeak_VOICE C structure
class EspeakVoice {
  final String name; // a given name for this voice. UTF8 string.
  final String languages; // list of pairs of (byte) priority + (string) language (and dialect qualifier)
  final String identifier; // the filename for this voice within espeak-ng-data/voices
  final Gender gender; // gender of the voice (none, male, female)
  final int age; // 0=not specified, or age in years
  final int variant; // only used when passed as a parameter to espeak_SetVoiceByProperties
  final int xx1; // for internal use (this should be private as per Dart conventions)
  final int score; // for internal use (also should be private)
  final dynamic spare; // for internal use (also should be private)

  const EspeakVoice({
    required this.name,
    required this.languages,
    required this.identifier,
    required this.gender,
    this.age = 0,
    this.variant = 0,
    this.xx1 = 0,
    this.score = 0,
    this.spare,
  });
}