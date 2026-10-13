import 'dart:math' as math;
import 'dart:typed_data';

/// Whisper's audio window: 30 seconds of 16 kHz mono audio.
const whisperSampleRate = 16000;
const whisperMaxSamples = 30 * whisperSampleRate;
const whisperMelBins = 80;
const whisperFrames = 3000;

const _fftSize = 400;
const _hopLength = 160;
const _bins = _fftSize ~/ 2 + 1;
const _halfSize = _fftSize ~/ 2;

/// Computes Whisper's log-mel spectrogram of [samples].
///
/// This matches Hugging Face's `WhisperFeatureExtractor`: the audio is padded
/// with zeros to 30 s, the STFT uses a periodic Hann window of 400 samples, a
/// hop of 160 samples, and reflect padding, and the 80 mel filters use the
/// Slaney scale and norm. The result is 80 rows of 3000 frames.
Float32List whisperLogMel(Float32List samples) {
  if (samples.length > whisperMaxSamples) {
    throw ArgumentError.value(
      samples.length,
      'samples.length',
      'Whisper accepts at most 30 seconds of audio',
    );
  }
  final tables = _Tables.instance;
  // The signal is the audio, zero-padded to 30 s, with 200 reflected samples
  // at each end.
  final signal = Float64List(whisperMaxSamples + _fftSize);
  for (var i = 0; i < samples.length; i++) {
    signal[_halfSize + i] = samples[i];
  }
  for (var i = 0; i < _halfSize; i++) {
    signal[_halfSize - 1 - i] = signal[_halfSize + 1 + i];
    signal[_halfSize + whisperMaxSamples + i] =
        signal[_halfSize + whisperMaxSamples - 2 - i];
  }

  final output = Float32List(whisperMelBins * whisperFrames);
  const floor = -10.0; // log10(1e-10)
  // A frame that starts after the audio is all zeros; its log-mel is floor.
  // When the audio reaches the reflected tail, this count is all frames.
  final liveFrames = math.min(
    whisperFrames,
    (_halfSize + samples.length + _hopLength - 1) ~/ _hopLength,
  );
  final fft = _RealFft400(tables);
  final power = Float64List(_bins);
  var maximum = floor;
  for (var frame = 0; frame < whisperFrames; frame++) {
    if (frame >= liveFrames) {
      for (var mel = 0; mel < whisperMelBins; mel++) {
        output[mel * whisperFrames + frame] = floor;
      }
      continue;
    }
    fft.power(signal, frame * _hopLength, power);
    for (var mel = 0; mel < whisperMelBins; mel++) {
      final start = tables.filterStart[mel];
      final weights = tables.filterWeights[mel];
      var sum = 0.0;
      for (var k = 0; k < weights.length; k++) {
        sum += weights[k] * power[start + k];
      }
      final value = math.log(math.max(sum, 1e-10)) / math.ln10;
      output[mel * whisperFrames + frame] = value;
      if (value > maximum) maximum = value;
    }
  }
  final lowest = maximum - 8.0;
  for (var i = 0; i < output.length; i++) {
    output[i] = (math.max(output[i], lowest) + 4.0) / 4.0;
  }
  return output;
}

final class _Tables {
  _Tables._() {
    for (var i = 0; i < _fftSize; i++) {
      window[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / _fftSize);
    }
    for (var i = 0; i < _fftSize; i++) {
      cos400[i] = math.cos(-2 * math.pi * i / _fftSize);
      sin400[i] = math.sin(-2 * math.pi * i / _fftSize);
    }
    _buildMelFilters();
  }

  static final instance = _Tables._();

  final window = Float64List(_fftSize);
  // exp(-2πi·j/400). The 200-point FFT uses the even entries.
  final cos400 = Float64List(_fftSize);
  final sin400 = Float64List(_fftSize);
  final filterStart = Int32List(whisperMelBins);
  final filterWeights = List<Float64List>.filled(
    whisperMelBins,
    Float64List(0),
  );

  void _buildMelFilters() {
    final fftFrequencies = List<double>.generate(
      _bins,
      (k) => k * (whisperSampleRate / 2) / (_bins - 1),
    );
    final low = _hzToMel(0);
    final high = _hzToMel(whisperSampleRate / 2);
    final points = List<double>.generate(
      whisperMelBins + 2,
      (i) => _melToHz(low + (high - low) * i / (whisperMelBins + 1)),
    );
    for (var mel = 0; mel < whisperMelBins; mel++) {
      final left = points[mel];
      final center = points[mel + 1];
      final right = points[mel + 2];
      final norm = 2.0 / (right - left);
      final weights = <double>[];
      var start = -1;
      for (var k = 0; k < _bins; k++) {
        final f = fftFrequencies[k];
        final rising = (f - left) / (center - left);
        final falling = (right - f) / (right - center);
        final weight = math.max(0.0, math.min(rising, falling)) * norm;
        if (weight > 0) {
          if (start < 0) start = k;
          // Weights are contiguous: zero only before and after the triangle.
          while (start + weights.length < k) {
            weights.add(0);
          }
          weights.add(weight);
        }
      }
      filterStart[mel] = math.max(start, 0);
      filterWeights[mel] = Float64List.fromList(weights);
    }
  }

  // Slaney mel scale: linear below 1 kHz, logarithmic above.
  static const _linearStep = 200.0 / 3;
  static const _logStart = 15.0; // 1000 Hz / _linearStep
  static final _logStep = math.log(6.4) / 27.0;

  static double _hzToMel(double hz) => hz >= 1000
      ? _logStart + math.log(hz / 1000) / _logStep
      : hz / _linearStep;

  static double _melToHz(double mel) => mel >= _logStart
      ? 1000 * math.exp(_logStep * (mel - _logStart))
      : mel * _linearStep;
}

/// Power spectrum of one windowed 400-sample frame.
///
/// It packs the even and odd samples into one 200-point complex FFT and
/// splits the result into the 201 bins of the real 400-point FFT.
final class _RealFft400 {
  _RealFft400(this._tables);

  final _Tables _tables;
  final _inRe = Float64List(_halfSize);
  final _inIm = Float64List(_halfSize);
  final _re = Float64List(_halfSize);
  final _im = Float64List(_halfSize);
  final _tRe = Float64List(5);
  final _tIm = Float64List(5);

  void power(Float64List signal, int offset, Float64List out) {
    final window = _tables.window;
    for (var n = 0; n < _halfSize; n++) {
      _inRe[n] = signal[offset + 2 * n] * window[2 * n];
      _inIm[n] = signal[offset + 2 * n + 1] * window[2 * n + 1];
    }
    _fft(0, 1, _halfSize, 0);
    final cos = _tables.cos400;
    final sin = _tables.sin400;
    for (var k = 0; k <= _halfSize; k++) {
      final a = k % _halfSize;
      final b = (_halfSize - k) % _halfSize;
      // E = (Z[k] + conj(Z[N-k])) / 2, O = (Z[k] - conj(Z[N-k])) / 2i.
      final eRe = (_re[a] + _re[b]) / 2;
      final eIm = (_im[a] - _im[b]) / 2;
      final oRe = (_im[a] + _im[b]) / 2;
      final oIm = -(_re[a] - _re[b]) / 2;
      // X[k] = E + W^k O, W = exp(-2πi/400).
      final wRe = k == _halfSize ? -1.0 : cos[k];
      final wIm = k == _halfSize ? 0.0 : sin[k];
      final xRe = eRe + wRe * oRe - wIm * oIm;
      final xIm = eIm + wRe * oIm + wIm * oRe;
      out[k] = xRe * xRe + xIm * xIm;
    }
  }

  /// Mixed-radix decimation in time. Reads _inRe/_inIm from [inOffset] with
  /// [stride] and writes [n] outputs to _re/_im at [outOffset].
  void _fft(int inOffset, int stride, int n, int outOffset) {
    if (n == 1) {
      _re[outOffset] = _inRe[inOffset];
      _im[outOffset] = _inIm[inOffset];
      return;
    }
    final p = n % 5 == 0 ? 5 : 2;
    final m = n ~/ p;
    for (var q = 0; q < p; q++) {
      _fft(inOffset + q * stride, stride * p, m, outOffset + q * m);
    }
    final cos = _tables.cos400;
    final sin = _tables.sin400;
    // Twiddles for size n are exp(-2πi·j/n) = W400^(j·400/n).
    final step = _fftSize ~/ n;
    if (p == 2) {
      for (var k = 0; k < m; k++) {
        final w = k * step;
        final i0 = outOffset + k;
        final i1 = i0 + m;
        final bRe = _re[i1] * cos[w] - _im[i1] * sin[w];
        final bIm = _re[i1] * sin[w] + _im[i1] * cos[w];
        final aRe = _re[i0];
        final aIm = _im[i0];
        _re[i0] = aRe + bRe;
        _im[i0] = aIm + bIm;
        _re[i1] = aRe - bRe;
        _im[i1] = aIm - bIm;
      }
      return;
    }
    const pStep = _fftSize ~/ 5;
    for (var k = 0; k < m; k++) {
      for (var q = 0; q < 5; q++) {
        final w = (q * k * step) % _fftSize;
        final i = outOffset + q * m + k;
        _tRe[q] = _re[i] * cos[w] - _im[i] * sin[w];
        _tIm[q] = _re[i] * sin[w] + _im[i] * cos[w];
      }
      for (var j = 0; j < 5; j++) {
        var sumRe = 0.0;
        var sumIm = 0.0;
        for (var q = 0; q < 5; q++) {
          final w = ((j * q) % 5) * pStep;
          sumRe += _tRe[q] * cos[w] - _tIm[q] * sin[w];
          sumIm += _tRe[q] * sin[w] + _tIm[q] * cos[w];
        }
        _re[outOffset + j * m + k] = sumRe;
        _im[outOffset + j * m + k] = sumIm;
      }
    }
  }
}
