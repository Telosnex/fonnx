import 'dart:math' as math;
import 'dart:typed_data';

/// Streaming Kaldi-compatible frontend for the fixed English KWS model.
///
/// Deliberately fixed to 16 kHz, 80 mel bins, 25 ms Povey windows, 10 ms
/// shifts, no dither, and `snip_edges=false`.
final class StreamingKwsFbank {
  StreamingKwsFbank() : _window = _makePoveyWindow(), _melBins = _makeMelBins();

  static const sampleRate = 16000;
  static const featureDimension = 80;
  static const _frameShift = 160;
  static const _frameLength = 400;
  static const _fftSize = 512;
  static const _floatEpsilon = 1.1920928955078125e-7;

  final Float32List _window;
  final List<_MelBin> _melBins;
  final List<double> _samples = <double>[];
  final List<Float32List> _frames = <Float32List>[];
  var _sampleOffset = 0;
  var _firstFrame = 0;
  var _framesGenerated = 0;
  var _finished = false;

  int get numFramesReady => _firstFrame + _frames.length;

  void accept(Float32List samples) {
    if (_finished) {
      throw StateError('Cannot accept audio after finish');
    }
    _samples.addAll(samples);
    _computeAvailableFrames(flush: false);
  }

  void finish() {
    if (_finished) return;
    _finished = true;
    _computeAvailableFrames(flush: true);
  }

  Float32List getFrames(int firstFrame, int count) {
    if (firstFrame < _firstFrame || firstFrame + count > numFramesReady) {
      throw RangeError(
        'Feature frames $firstFrame..${firstFrame + count} unavailable',
      );
    }
    final result = Float32List(count * featureDimension);
    for (var i = 0; i < count; i++) {
      result.setRange(
        i * featureDimension,
        (i + 1) * featureDimension,
        _frames[firstFrame - _firstFrame + i],
      );
    }
    return result;
  }

  void discardBefore(int frame) {
    final count = math.min(frame - _firstFrame, _frames.length);
    if (count <= 0) return;
    _frames.removeRange(0, count);
    _firstFrame += count;
  }

  void reset() {
    _samples.clear();
    _frames.clear();
    _sampleOffset = 0;
    _firstFrame = 0;
    _framesGenerated = 0;
    _finished = false;
  }

  void _computeAvailableFrames({required bool flush}) {
    final totalSamples = _sampleOffset + _samples.length;
    final newFrameCount = _numFrames(totalSamples, flush: flush);
    for (var frame = _framesGenerated; frame < newFrameCount; frame++) {
      _frames.add(_computeFrame(frame));
    }
    _framesGenerated = newFrameCount;

    final firstNeededSample = _firstSampleOfFrame(newFrameCount);
    final discardCount = firstNeededSample - _sampleOffset;
    if (discardCount > 0) {
      final actual = math.min(discardCount, _samples.length);
      _samples.removeRange(0, actual);
      _sampleOffset += actual;
    }
  }

  int _numFrames(int sampleCount, {required bool flush}) {
    var frames = (sampleCount + _frameShift ~/ 2) ~/ _frameShift;
    if (flush) return frames;
    var end = _firstSampleOfFrame(frames - 1) + _frameLength;
    while (frames > 0 && end > sampleCount) {
      frames--;
      end -= _frameShift;
    }
    return frames;
  }

  static int _firstSampleOfFrame(int frame) =>
      _frameShift * frame + _frameShift ~/ 2 - _frameLength ~/ 2;

  Float32List _computeFrame(int frame) {
    final padded = Float32List(_fftSize);
    final start = _firstSampleOfFrame(frame);
    for (var i = 0; i < _frameLength; i++) {
      var sample = start + i - _sampleOffset;
      while (sample < 0 || sample >= _samples.length) {
        if (sample < 0) {
          sample = -sample - 1;
        } else {
          sample = 2 * _samples.length - 1 - sample;
        }
      }
      padded[i] = _samples[sample];
    }

    var mean = 0.0;
    for (var i = 0; i < _frameLength; i++) {
      mean += padded[i];
    }
    mean /= _frameLength;
    for (var i = 0; i < _frameLength; i++) {
      padded[i] -= mean;
    }
    for (var i = _frameLength - 1; i > 0; i--) {
      padded[i] -= 0.97 * padded[i - 1];
    }
    padded[0] -= 0.97 * padded[0];
    for (var i = 0; i < _frameLength; i++) {
      padded[i] *= _window[i];
    }

    final power = _powerSpectrum(padded);
    final features = Float32List(featureDimension);
    for (var bin = 0; bin < featureDimension; bin++) {
      final mel = _melBins[bin];
      var energy = 0.0;
      for (var i = 0; i < mel.weights.length; i++) {
        energy += mel.weights[i] * power[mel.offset + i];
      }
      features[bin] = math.log(math.max(energy, _floatEpsilon));
    }
    return features;
  }

  static Float32List _makePoveyWindow() {
    final result = Float32List(_frameLength);
    final scale = 2 * math.pi / (_frameLength - 1);
    for (var i = 0; i < result.length; i++) {
      result[i] = math.pow(0.5 - 0.5 * math.cos(scale * i), 0.85).toDouble();
    }
    return result;
  }

  static List<_MelBin> _makeMelBins() {
    const lowFrequency = 20.0;
    const highFrequency = 7600.0;
    const fftBinWidth = sampleRate / _fftSize;
    final lowMel = _melScale(lowFrequency);
    final highMel = _melScale(highFrequency);
    final delta = (highMel - lowMel) / (featureDimension + 1);
    final bins = <_MelBin>[];

    for (var bin = 0; bin < featureDimension; bin++) {
      final left = lowMel + bin * delta;
      final center = lowMel + (bin + 1) * delta;
      final right = lowMel + (bin + 2) * delta;
      var first = -1;
      var last = -1;
      final allWeights = Float32List(_fftSize ~/ 2);
      for (var i = 0; i < allWeights.length; i++) {
        final mel = _melScale(fftBinWidth * i);
        if (mel > left && mel < right) {
          allWeights[i] = mel <= center
              ? (mel - left) / (center - left)
              : (right - mel) / (right - center);
          first = first == -1 ? i : first;
          last = i;
        }
      }
      if (first == -1) {
        throw StateError('Invalid mel filter configuration');
      }
      bins.add(
        _MelBin(
          first,
          Float32List.fromList(allWeights.sublist(first, last + 1)),
        ),
      );
    }
    return bins;
  }

  static double _melScale(double frequency) =>
      1127 * math.log(1 + frequency / 700);

  static Float32List _powerSpectrum(Float32List samples) {
    final real = Float64List.fromList(samples);
    final imaginary = Float64List(samples.length);
    _fft(real, imaginary);
    final power = Float32List(samples.length ~/ 2 + 1);
    for (var i = 0; i < power.length; i++) {
      // kaldi-native-fbank casts FFT output to float before squaring.
      final floatParts = Float32List(2)
        ..[0] = real[i]
        ..[1] = imaginary[i];
      power[i] = floatParts[0] * floatParts[0] + floatParts[1] * floatParts[1];
    }
    return power;
  }

  static void _fft(Float64List real, Float64List imaginary) {
    final length = real.length;
    for (var i = 1, j = 0; i < length; i++) {
      var bit = length >> 1;
      for (; (j & bit) != 0; bit >>= 1) {
        j ^= bit;
      }
      j ^= bit;
      if (i < j) {
        final realValue = real[i];
        real[i] = real[j];
        real[j] = realValue;
        final imaginaryValue = imaginary[i];
        imaginary[i] = imaginary[j];
        imaginary[j] = imaginaryValue;
      }
    }

    for (var size = 2; size <= length; size <<= 1) {
      final angle = -2 * math.pi / size;
      final stepReal = math.cos(angle);
      final stepImaginary = math.sin(angle);
      for (var start = 0; start < length; start += size) {
        var phaseReal = 1.0;
        var phaseImaginary = 0.0;
        for (var offset = 0; offset < size ~/ 2; offset++) {
          final even = start + offset;
          final odd = even + size ~/ 2;
          final oddReal =
              real[odd] * phaseReal - imaginary[odd] * phaseImaginary;
          final oddImaginary =
              real[odd] * phaseImaginary + imaginary[odd] * phaseReal;
          real[odd] = real[even] - oddReal;
          imaginary[odd] = imaginary[even] - oddImaginary;
          real[even] += oddReal;
          imaginary[even] += oddImaginary;
          final nextReal =
              phaseReal * stepReal - phaseImaginary * stepImaginary;
          phaseImaginary =
              phaseReal * stepImaginary + phaseImaginary * stepReal;
          phaseReal = nextReal;
        }
      }
    }
  }
}

final class _MelBin {
  const _MelBin(this.offset, this.weights);

  final int offset;
  final Float32List weights;
}
