import 'dart:typed_data';

extension AudioFloatsFromListInt on List<int> {
  Float32List toAudioFloat32List() {
    Float32List audioData = Float32List((length ~/ 2));

    for (int i = 0; i < audioData.length; i++) {
      // Combine two bytes to form a 16-bit integer value and normalize
      int val = (this[i * 2] & 0xff) | (this[i * 2 + 1] << 8);
      // If the 16-bit integer exceeds 32767 (max positive value for a signed 16-bit int),
      // it should be interpreted as a negative number. This is a quick way to do that.
      if (val > 0x7FFF) {
        val = val - 0x10000;
      }
      // Normalization to [-1.0, 1.0] range for float32 representation
      // Divide by the maximum value for a signed 16-bit integer
      audioData[i] = val / 32767.0;
    }
    return audioData;
  }
}