import 'dart:math' as math;
import 'dart:typed_data';

class WavHeader {
  static const RIFF = ['R', 'I', 'F', 'F']; // 'RIFF'
  static const WAVE = ['W', 'A', 'V', 'E']; // 'WAVE'
  static const fmt = ['f', 'm', 't', ' ']; // 'fmt '
  static const data = ['d', 'a', 't', 'a']; // 'data'

  int chunkSize;
  int fmtSize = 16; // bytes
  int audioFormat = 1; // PCM
  int numChannels;
  int sampleRate;
  int bytesPerSec; // sampleRate * sampleWidth
  int blockAlign; // mono or stereo * sampleWidth
  int bitsPerSample;
  int dataSize;

  WavHeader._({
    required this.chunkSize,
    required this.numChannels,
    required this.sampleRate,
    required this.bytesPerSec,
    required this.blockAlign,
    required this.bitsPerSample,
    required this.dataSize,
  });

  factory WavHeader({
    required int sampleRate,
    required int sampleWidth,
    required int numChannels,
    required int numSamples,
  }) {
    int bitsPerSample = sampleWidth * 8;
    int bytesPerSec = sampleRate * sampleWidth * numChannels;
    int blockAlign = sampleWidth * numChannels;
    int dataSize = numSamples * sampleWidth * numChannels;
    int chunkSize = 36 + dataSize;

    return WavHeader._(
      chunkSize: chunkSize,
      numChannels: numChannels,
      sampleRate: sampleRate,
      bytesPerSec: bytesPerSec,
      blockAlign: blockAlign,
      bitsPerSample: bitsPerSample,
      dataSize: dataSize,
    );
  }

  Uint8List getBytes() {
    final buffer = ByteData(44); // WAV headers are always 44 bytes

    // 'RIFF'
    _setStringBytes(buffer, 0, RIFF);
    // 'chunkSize'
    buffer.setUint32(4, chunkSize, Endian.little);
    // 'WAVE'
    _setStringBytes(buffer, 8, WAVE);
    // 'fmt '
    _setStringBytes(buffer, 12, fmt);
    // 'fmtSize', 'audioFormat'
    buffer.setUint32(16, fmtSize, Endian.little);
    buffer.setUint16(20, audioFormat, Endian.little);
    // 'numChannels', 'sampleRate'
    buffer.setUint16(22, numChannels, Endian.little);
    buffer.setUint32(24, sampleRate, Endian.little);
    // 'bytesPerSec', 'blockAlign', 'bitsPerSample'
    buffer.setUint32(28, bytesPerSec, Endian.little);
    buffer.setUint16(32, blockAlign, Endian.little);
    buffer.setUint16(34, bitsPerSample, Endian.little);
    // 'data', 'dataSize'
    _setStringBytes(buffer, 36, data);
    buffer.setUint32(40, dataSize, Endian.little);

    return buffer.buffer.asUint8List();
  }

  void _setStringBytes(ByteData buffer, int offset, List<String> str) {
    for (var i = 0; i < str.length; i++) {
      buffer.setUint8(offset + i, str[i].codeUnitAt(0));
    }
  }
}


Int16List convertFloat32ToInt16(Float32List audio) {
  // Define the maximum and minimum values for Int16 to avoid magic numbers.
  const int maxInt16Value = 32767;
  const int minInt16Value = -32768;

  // Find the maximum absolute value in the audio buffer to determine the scaling factor.
  // This avoids dividing by zero if the maximum value in the audio is very small or zero.
  final maxAudioValue = audio.fold<double>(
      0.0, (maxValue, value) => math.max(maxValue, value.abs()));
  final audioScaleFactor =
      math.max(maxInt16Value / math.max(maxAudioValue, 0.01), 0.01);

  // Initialize the Int16List to store the converted audio data.
  final Int16List audioBuffer = Int16List(audio.length);

  // Scale audio to fill the Int16 range and convert to Int16 while clamping the values.
  for (int i = 0; i < audio.length; i++) {
    // Scale the float value.
    final int scaledValue = (audio[i] * audioScaleFactor).toInt();
    // Clamp the scaled value within the Int16 range to avoid overflow/underflow.
    audioBuffer[i] = scaledValue.clamp(minInt16Value, maxInt16Value);
  }

  return audioBuffer;
}
