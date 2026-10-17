/// Kokoro token ids, voice styles and WAV output. Platform-neutral.
library;

import 'dart:typed_data';

import 'package:fonnx/models/kokoro/kokoro_vocab.dart';

const kokoroSampleRate = 24000;
const kokoroStyleDim = 256;

/// Kokoro's context is 512 tokens including the two pad tokens.
const kokoroMaxPhonemeTokens = 510;

/// Converts a misaki phoneme string to Kokoro token ids, without pads.
///
/// Mirrors the upstream tokenizer.json: characters outside the vocabulary are
/// dropped, every remaining character is one token.
List<int> kokoroPhonemesToIds(String phonemes) {
  final ids = <int>[];
  for (final rune in phonemes.runes) {
    final id = kokoroVocab[String.fromCharCode(rune)];
    if (id != null) ids.add(id);
  }
  if (ids.length > kokoroMaxPhonemeTokens) {
    throw ArgumentError.value(
      ids.length,
      'phonemes',
      'Kokoro accepts at most $kokoroMaxPhonemeTokens phoneme tokens; '
          'split the text into chunks first',
    );
  }
  return ids;
}

/// Selects the style row for an utterance of [tokenCount] phoneme tokens.
///
/// Voice files are float32 arrays shaped [510, 1, 256]; upstream indexes the
/// row by the unpadded phoneme count minus one.
Float32List kokoroStyleForLength(Float32List voice, int tokenCount) {
  final rows = voice.length ~/ kokoroStyleDim;
  if (rows == 0 || voice.length % kokoroStyleDim != 0) {
    throw ArgumentError('Voice data is not a multiple of $kokoroStyleDim');
  }
  if (tokenCount < 1 || tokenCount > kokoroMaxPhonemeTokens) {
    throw ArgumentError.value(tokenCount, 'tokenCount');
  }
  final row = (tokenCount - 1).clamp(0, rows - 1);
  return Float32List.sublistView(
    voice,
    row * kokoroStyleDim,
    (row + 1) * kokoroStyleDim,
  );
}

/// Encodes mono float PCM as a 16-bit WAV file.
Uint8List kokoroWav(Float32List samples, {int sampleRate = kokoroSampleRate}) {
  final dataBytes = samples.length * 2;
  final out = ByteData(44 + dataBytes);
  void ascii(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      out.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  out.setUint32(4, 36 + dataBytes, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  out.setUint32(16, 16, Endian.little);
  out.setUint16(20, 1, Endian.little);
  out.setUint16(22, 1, Endian.little);
  out.setUint32(24, sampleRate, Endian.little);
  out.setUint32(28, sampleRate * 2, Endian.little);
  out.setUint16(32, 2, Endian.little);
  out.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  out.setUint32(40, dataBytes, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    final s = (samples[i].clamp(-1.0, 1.0) * 32767).round();
    out.setInt16(44 + i * 2, s, Endian.little);
  }
  return out.buffer.asUint8List();
}

/// Kokoro voice files hold float32 values shaped [510, 1, 256].
const kokoroVoiceBytes = kokoroMaxPhonemeTokens * kokoroStyleDim * 4;

/// Reads a little-endian float32 voice file named [name].
Float32List kokoroParseVoice(Uint8List bytes, String name) {
  if (bytes.length != kokoroVoiceBytes) {
    throw FormatException('Invalid Kokoro voice shape: $name');
  }
  final data = ByteData.sublistView(bytes);
  final values = Float32List(bytes.length ~/ 4);
  for (var i = 0; i < values.length; i++) {
    values[i] = data.getFloat32(i * 4, Endian.little);
  }
  if (values.any((v) => !v.isFinite)) {
    throw FormatException('Nonfinite voice values: $name');
  }
  return values;
}
