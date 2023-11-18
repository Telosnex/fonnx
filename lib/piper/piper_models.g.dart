// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'piper_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$PiperSynthesisConfigImpl _$$PiperSynthesisConfigImplFromJson(
        Map<String, dynamic> json) =>
    _$PiperSynthesisConfigImpl(
      noiseScale: (json['noiseScale'] as num?)?.toDouble() ?? 0.667,
      lengthScale: (json['lengthScale'] as num?)?.toDouble() ?? 1.0,
      noiseW: (json['noiseW'] as num?)?.toDouble() ?? 0.8,
      sampleRate: json['sampleRate'] as int? ?? 22050,
      sampleWidth: json['sampleWidth'] as int? ?? 2,
      channels: json['channels'] as int? ?? 1,
      speakerId: json['speakerId'] as int? ?? 0,
      sentenceSilenceSeconds:
          (json['sentenceSilenceSeconds'] as num?)?.toDouble() ?? 0.2,
      phonemeSilenceSeconds:
          (json['phonemeSilenceSeconds'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(k, (e as num).toDouble()),
      ),
    );

Map<String, dynamic> _$$PiperSynthesisConfigImplToJson(
        _$PiperSynthesisConfigImpl instance) =>
    <String, dynamic>{
      'noiseScale': instance.noiseScale,
      'lengthScale': instance.lengthScale,
      'noiseW': instance.noiseW,
      'sampleRate': instance.sampleRate,
      'sampleWidth': instance.sampleWidth,
      'channels': instance.channels,
      'speakerId': instance.speakerId,
      'sentenceSilenceSeconds': instance.sentenceSilenceSeconds,
      'phonemeSilenceSeconds': instance.phonemeSilenceSeconds,
    };

_$PiperConfigImpl _$$PiperConfigImplFromJson(Map<String, dynamic> json) =>
    _$PiperConfigImpl(
      audio: json['audio'] == null
          ? null
          : Audio.fromJson(json['audio'] as Map<String, dynamic>),
      espeak: json['espeak'] == null
          ? null
          : Espeak.fromJson(json['espeak'] as Map<String, dynamic>),
      inference: json['inference'] == null
          ? null
          : Inference.fromJson(json['inference'] as Map<String, dynamic>),
      phonemeType: json['phoneme_type'] as String?,
      phonemeMap: (json['phoneme_map'] as Map<String, dynamic>?)?.map(
        (k, e) =>
            MapEntry(k, (e as List<dynamic>).map((e) => e as int).toList()),
      ),
      phonemeIdMap: (json['phoneme_id_map'] as Map<String, dynamic>?)?.map(
        (k, e) =>
            MapEntry(k, (e as List<dynamic>).map((e) => e as int).toList()),
      ),
      numSymbols: json['num_symbols'] as int?,
      numSpeakers: json['num_speakers'] as int?,
      speakerIdMap: (json['speaker_id_map'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(k, e as int),
      ),
      piperVersion: json['piper_version'] as String?,
      language: json['language'] == null
          ? null
          : Language.fromJson(json['language'] as Map<String, dynamic>),
      dataset: json['dataset'] as String?,
    );

Map<String, dynamic> _$$PiperConfigImplToJson(_$PiperConfigImpl instance) =>
    <String, dynamic>{
      'audio': instance.audio,
      'espeak': instance.espeak,
      'inference': instance.inference,
      'phoneme_type': instance.phonemeType,
      'phoneme_map': instance.phonemeMap,
      'phoneme_id_map': instance.phonemeIdMap,
      'num_symbols': instance.numSymbols,
      'num_speakers': instance.numSpeakers,
      'speaker_id_map': instance.speakerIdMap,
      'piper_version': instance.piperVersion,
      'language': instance.language,
      'dataset': instance.dataset,
    };

_$AudioImpl _$$AudioImplFromJson(Map<String, dynamic> json) => _$AudioImpl(
      sampleRate: json['sample_rate'] as int?,
      quality: json['quality'] as String?,
    );

Map<String, dynamic> _$$AudioImplToJson(_$AudioImpl instance) =>
    <String, dynamic>{
      'sample_rate': instance.sampleRate,
      'quality': instance.quality,
    };

_$EspeakImpl _$$EspeakImplFromJson(Map<String, dynamic> json) => _$EspeakImpl(
      voice: json['voice'] as String?,
    );

Map<String, dynamic> _$$EspeakImplToJson(_$EspeakImpl instance) =>
    <String, dynamic>{
      'voice': instance.voice,
    };

_$InferenceImpl _$$InferenceImplFromJson(Map<String, dynamic> json) =>
    _$InferenceImpl(
      noiseScale: (json['noise_scale'] as num?)?.toDouble(),
      lengthScale: (json['length_scale'] as num?)?.toDouble(),
      noiseW: (json['noise_w'] as num?)?.toDouble(),
    );

Map<String, dynamic> _$$InferenceImplToJson(_$InferenceImpl instance) =>
    <String, dynamic>{
      'noise_scale': instance.noiseScale,
      'length_scale': instance.lengthScale,
      'noise_w': instance.noiseW,
    };

_$LanguageImpl _$$LanguageImplFromJson(Map<String, dynamic> json) =>
    _$LanguageImpl(
      code: json['code'] as String?,
      family: json['family'] as String?,
      region: json['region'] as String?,
      nameNative: json['name_native'] as String?,
      nameEnglish: json['name_english'] as String?,
      countryEnglish: json['country_english'] as String?,
    );

Map<String, dynamic> _$$LanguageImplToJson(_$LanguageImpl instance) =>
    <String, dynamic>{
      'code': instance.code,
      'family': instance.family,
      'region': instance.region,
      'name_native': instance.nameNative,
      'name_english': instance.nameEnglish,
      'country_english': instance.countryEnglish,
    };
