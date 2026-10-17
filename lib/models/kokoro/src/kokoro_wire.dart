import '../kokoro.dart';

/// The JSON that carries a bundle and chunk policy to the web Worker.
/// [resolve] maps each bundle location, for example to an absolute URL.
Map<String, Object?> kokoroLoadRequestToJson(
  KokoroBundle bundle,
  KokoroChunkPolicy policy, {
  String Function(String location)? resolve,
}) {
  final r = resolve ?? (String s) => s;
  return {
    'bundle': {
      'prosodyModel': r(bundle.prosodyModel),
      'decoderModel': r(bundle.decoderModel),
      'spacyConfig': r(bundle.spacyConfig),
      'spacyWeights': r(bundle.spacyWeights),
      'usGold': r(bundle.usGold),
      'usSilver': r(bundle.usSilver),
      'gbGold': r(bundle.gbGold),
      'gbSilver': r(bundle.gbSilver),
      'fallbackModel': r(bundle.fallbackModel),
      'fallbackConfig': r(bundle.fallbackConfig),
      'voices': {
        for (final MapEntry(:key, :value) in bundle.voices.entries)
          key: {'path': r(value.path), 'language': value.language.name},
      },
    },
    'policy': {
      'firstChunkSeconds': policy.firstChunkSeconds,
      'toleranceSeconds': policy.toleranceSeconds,
      'crossfadeSeconds': policy.crossfadeSeconds,
      'growth': policy.growth,
      'padFrames': policy.padFrames,
      'decodeSpeechFrames': policy.decodeSpeechFrames,
    },
  };
}

(KokoroBundle, KokoroChunkPolicy) kokoroLoadRequestFromJson(
  Map<String, dynamic> json,
) {
  final b = json['bundle'] as Map<String, dynamic>;
  final p = json['policy'] as Map<String, dynamic>;
  final bundle = KokoroBundle(
    prosodyModel: b['prosodyModel'] as String,
    decoderModel: b['decoderModel'] as String,
    spacyConfig: b['spacyConfig'] as String,
    spacyWeights: b['spacyWeights'] as String,
    usGold: b['usGold'] as String,
    usSilver: b['usSilver'] as String,
    gbGold: b['gbGold'] as String,
    gbSilver: b['gbSilver'] as String,
    fallbackModel: b['fallbackModel'] as String,
    fallbackConfig: b['fallbackConfig'] as String,
    voices: {
      for (final MapEntry(:key, :value)
          in (b['voices'] as Map<String, dynamic>).entries)
        key: KokoroVoice(
          path: (value as Map<String, dynamic>)['path'] as String,
          language: KokoroLanguage.values.byName(value['language'] as String),
        ),
    },
  );
  final policy = KokoroChunkPolicy(
    firstChunkSeconds: (p['firstChunkSeconds'] as num).toDouble(),
    toleranceSeconds: (p['toleranceSeconds'] as num).toDouble(),
    crossfadeSeconds: (p['crossfadeSeconds'] as num).toDouble(),
    growth: (p['growth'] as num).toDouble(),
    padFrames: p['padFrames'] as int,
    decodeSpeechFrames: p['decodeSpeechFrames'] as int,
  )..validate();
  return (bundle, policy);
}
