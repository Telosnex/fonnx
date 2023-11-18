import 'package:freezed_annotation/freezed_annotation.dart';

part 'piper_models.freezed.dart';
part 'piper_models.g.dart';

@freezed
class PiperSynthesisConfig with _$PiperSynthesisConfig {
  factory PiperSynthesisConfig({
    @Default(0.667) double noiseScale,
    @Default(1.0) double lengthScale,
    @Default(0.8) double noiseW,
    @Default(22050) int sampleRate,
    @Default(2) int sampleWidth,
    @Default(1) int channels,
    @Default(0) int speakerId,
    @Default(0.2) double sentenceSilenceSeconds,
    Map<String, double>? phonemeSilenceSeconds,
  }) = _PiperSynthesisConfig;

  factory PiperSynthesisConfig.fromJson(Map<String, dynamic> json) =>
      _$PiperSynthesisConfigFromJson(json);
}

@freezed
class PiperConfig with _$PiperConfig {
  factory PiperConfig({
    Audio? audio,
    Espeak? espeak,
    Inference? inference,
    @JsonKey(name: 'phoneme_type') String? phonemeType,
    @JsonKey(name: 'phoneme_map') Map<String, List<int>>? phonemeMap,
    @JsonKey(name: 'phoneme_id_map') Map<String, List<int>>? phonemeIdMap,
    @JsonKey(name: 'num_symbols') int? numSymbols,
    @JsonKey(name: 'num_speakers') int? numSpeakers,
    @JsonKey(name: 'speaker_id_map') Map<String, int>? speakerIdMap,
    @JsonKey(name: 'piper_version') String? piperVersion,
    Language? language,
    String? dataset,
  }) = _PiperConfig;

  factory PiperConfig.fromJson(Map<String, dynamic> json) =>
      _$PiperConfigFromJson(json);
}

@freezed
class Audio with _$Audio {
  factory Audio({
    @JsonKey(name: 'sample_rate') int? sampleRate,
    String? quality,
  }) = _Audio;

  factory Audio.fromJson(Map<String, dynamic> json) => _$AudioFromJson(json);
}

@freezed
class Espeak with _$Espeak {
  factory Espeak({
    String? voice,
  }) = _Espeak;

  factory Espeak.fromJson(Map<String, dynamic> json) => _$EspeakFromJson(json);
}

@freezed
class Inference with _$Inference {
  factory Inference({
    @JsonKey(name: 'noise_scale') double? noiseScale,
    @JsonKey(name: 'length_scale') double? lengthScale,
    @JsonKey(name: 'noise_w') double? noiseW,
  }) = _Inference;

  factory Inference.fromJson(Map<String, dynamic> json) =>
      _$InferenceFromJson(json);
}

@freezed
class Language with _$Language {
  factory Language({
    String? code,
    String? family,
    String? region,
    @JsonKey(name: 'name_native') String? nameNative,
    @JsonKey(name: 'name_english') String? nameEnglish,
    @JsonKey(name: 'country_english') String? countryEnglish,
  }) = _Language;

  factory Language.fromJson(Map<String, dynamic> json) =>
      _$LanguageFromJson(json);
}
