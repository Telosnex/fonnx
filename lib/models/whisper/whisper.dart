import 'dart:typed_data';

import 'whisper_none.dart'
    if (dart.library.io) 'whisper_native.dart'
    if (dart.library.js_interop) 'whisper_web.dart';

/// The two ONNX files of a Whisper model, in the layout of the
/// `onnx-community/whisper-*` exports: an encoder, and a merged decoder with
/// a key/value cache.
final class WhisperBundle {
  const WhisperBundle({
    required this.encoderPath,
    required this.decoderPath,
    required this.decoderLayers,
    required this.attentionHeads,
  });

  /// Whisper tiny (multilingual): `whisper_tiny_encoder.onnx` and
  /// `whisper_tiny_decoder.onnx` in [directory]. On web, [directory] is a URL.
  factory WhisperBundle.tiny(String directory) {
    final separator = directory.endsWith('/') ? '' : '/';
    return WhisperBundle(
      encoderPath: '$directory${separator}whisper_tiny_encoder.onnx',
      decoderPath: '$directory${separator}whisper_tiny_decoder.onnx',
      decoderLayers: 4,
      attentionHeads: 6,
    );
  }

  final String encoderPath;
  final String decoderPath;

  /// Number of decoder layers. Each layer has one key/value cache.
  final int decoderLayers;

  /// Number of attention heads. Each head has 64 dimensions.
  final int attentionHeads;

  @override
  bool operator ==(Object other) =>
      other is WhisperBundle &&
      other.encoderPath == encoderPath &&
      other.decoderPath == decoderPath &&
      other.decoderLayers == decoderLayers &&
      other.attentionHeads == attentionHeads;

  @override
  int get hashCode =>
      Object.hash(encoderPath, decoderPath, decoderLayers, attentionHeads);

  @override
  String toString() => 'WhisperBundle($encoderPath, $decoderPath)';
}

/// English speech-to-text with Whisper.
abstract class Whisper {
  static Whisper? _instance;

  WhisperBundle get bundle;

  /// Returns the one Whisper instance. It loads the model on first use.
  static Whisper load(WhisperBundle bundle) {
    if ([
      bundle.encoderPath,
      bundle.decoderPath,
    ].any((path) => path.trim().isEmpty)) {
      throw ArgumentError.value(bundle, 'bundle', 'Paths must not be empty');
    }
    final current = _instance;
    if (current != null && current.bundle != bundle) {
      throw StateError('Whisper is already loaded from ${current.bundle}');
    }
    return _instance ??= getWhisper(bundle);
  }

  /// Transcribes [bytes]: 16-bit little-endian PCM, mono, 16 kHz, at most
  /// 30 seconds.
  Future<String> doInference(Uint8List bytes);
}
