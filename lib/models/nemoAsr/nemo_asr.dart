import 'dart:typed_data';

import 'nemo_asr_none.dart'
    if (dart.library.io) 'nemo_asr_native.dart'
    if (dart.library.js_interop) 'nemo_asr_web.dart';

import 'src/nemo_asr_features.dart';

/// The longest audio that [NemoAsr] transcribes: 60 seconds.
const nemoAsrMaxSamples = 60 * nemoAsrSampleRate;

/// The NeMo speech-to-text models that fonnx runs. Both are the int8 exports
/// of sherpa-onnx; see `example/assets/models/nemoAsr/README.md`.
enum NemoAsrModel {
  /// NVIDIA's multilingual FastConformer hybrid large model (114M
  /// parameters), CTC branch: Belarusian, Croatian, English, French, German,
  /// Italian, Polish, Russian, Spanish and Ukrainian. One file, 132 MB.
  fastConformerCtcMultilingual,

  /// NVIDIA's Parakeet TDT 0.6B v3: English and 24 other European languages.
  /// An encoder, a prediction network and a joiner, 670 MB.
  parakeetTdtV3,
}

/// The ONNX files of a [NemoAsrModel].
final class NemoAsrBundle {
  const NemoAsrBundle._(this.model, this.paths);

  /// `fastconformer_ctc_multilingual_int8.onnx` in [directory]. On web,
  /// [directory] is a URL.
  factory NemoAsrBundle.fastConformerCtcMultilingual(String directory) =>
      NemoAsrBundle.fastConformerCtcMultilingualFile(
        _join(directory, 'fastconformer_ctc_multilingual_int8.onnx'),
      );

  factory NemoAsrBundle.fastConformerCtcMultilingualFile(String modelPath) =>
      NemoAsrBundle._(NemoAsrModel.fastConformerCtcMultilingual, [modelPath]);

  /// `parakeet_tdt_v3_encoder_int8.onnx`, `parakeet_tdt_v3_decoder_int8.onnx`
  /// and `parakeet_tdt_v3_joiner_int8.onnx` in [directory]. On web,
  /// [directory] is a URL.
  factory NemoAsrBundle.parakeetTdtV3(String directory) =>
      NemoAsrBundle.parakeetTdtV3Files(
        encoderPath: _join(directory, 'parakeet_tdt_v3_encoder_int8.onnx'),
        decoderPath: _join(directory, 'parakeet_tdt_v3_decoder_int8.onnx'),
        joinerPath: _join(directory, 'parakeet_tdt_v3_joiner_int8.onnx'),
      );

  factory NemoAsrBundle.parakeetTdtV3Files({
    required String encoderPath,
    required String decoderPath,
    required String joinerPath,
  }) => NemoAsrBundle._(NemoAsrModel.parakeetTdtV3, [
    encoderPath,
    decoderPath,
    joinerPath,
  ]);

  final NemoAsrModel model;

  /// The model file for CTC. The encoder, decoder and joiner for TDT.
  final List<String> paths;

  static String _join(String directory, String name) =>
      '$directory${directory.endsWith('/') ? '' : '/'}$name';

  @override
  bool operator ==(Object other) =>
      other is NemoAsrBundle &&
      other.model == model &&
      other.paths.length == paths.length &&
      [
        for (var i = 0; i < paths.length; i++) other.paths[i] == paths[i],
      ].every((same) => same);

  @override
  int get hashCode => Object.hash(model, Object.hashAll(paths));

  @override
  String toString() => 'NemoAsrBundle(${model.name}, ${paths.join(', ')})';
}

/// Speech-to-text with a NeMo FastConformer or Parakeet model. The models
/// detect the language; there is no language setting.
abstract class NemoAsr {
  static final _instances = <NemoAsrModel, NemoAsr>{};

  NemoAsrBundle get bundle;

  /// Returns the one instance for the model of [bundle]. It loads the model
  /// on first use. Each [NemoAsrModel] can be loaded once, from one bundle.
  static NemoAsr load(NemoAsrBundle bundle) {
    if (bundle.paths.any((path) => path.trim().isEmpty)) {
      throw ArgumentError.value(bundle, 'bundle', 'Paths must not be empty');
    }
    final current = _instances[bundle.model];
    if (current != null && current.bundle != bundle) {
      throw StateError('NemoAsr is already loaded from ${current.bundle}');
    }
    return _instances[bundle.model] ??= getNemoAsr(bundle);
  }

  /// Transcribes [bytes]: 16-bit little-endian PCM, mono, 16 kHz, at most
  /// 60 seconds.
  Future<String> doInference(Uint8List bytes);
}
