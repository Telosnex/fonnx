import 'dart:math' as math;
import 'dart:typed_data';

const nemoAsrSampleRate = 16000;

const _fftSize = 512;
const _windowLength = 400;
const _hopLength = 160;
const _bins = _fftSize ~/ 2 + 1;
const _preemphasis = 0.97;
// log(x + 2^-24), as NeMo's log_zero_guard_value.
const _logGuard = 5.9604644775390625e-8;
const _stdGuard = 1e-5;

/// The number of feature frames for [samples] samples: one per 10 ms hop,
/// plus one.
int nemoAsrFrames(int samples) => samples ~/ _hopLength + 1;

/// Computes the log-mel features of NeMo's `AudioToMelSpectrogramPreprocessor`
/// with the settings of the FastConformer and Parakeet models: preemphasis
/// 0.97, a 512-point STFT of a symmetric 400-sample Hann window with a hop of
/// 160 and zero padding at both ends, a power spectrum, [melBins] Slaney mel
/// filters from 0 to 8 kHz, `log(x + 2^-24)`, and per-feature normalization
/// (mean 0, unbiased standard deviation 1).
///
/// The result is [melBins] rows of [nemoAsrFrames] frames, the layout of the
/// encoder input `audio_signal`.
Float32List nemoAsrLogMel(Float32List samples, int melBins) {
  final frames = nemoAsrFrames(samples.length);
  final tables = _Tables.forBins(melBins);
  // The preemphasized audio with 256 zeros at each end.
  const half = _fftSize ~/ 2;
  final signal = Float64List(samples.length + _fftSize);
  for (var i = 0; i < samples.length; i++) {
    final previous = i == 0 ? 0.0 : samples[i - 1] * _preemphasis;
    signal[half + i] = samples[i] - previous;
  }

  final output = Float32List(melBins * frames);
  final fft = _Fft512();
  final power = Float64List(_bins);
  final window = tables.window;
  for (var frame = 0; frame < frames; frame++) {
    fft.power(signal, frame * _hopLength, window, power);
    for (var mel = 0; mel < melBins; mel++) {
      final start = tables.filterStart[mel];
      final weights = tables.filterWeights[mel];
      var sum = 0.0;
      for (var k = 0; k < weights.length; k++) {
        sum += weights[k] * power[start + k];
      }
      output[mel * frames + frame] = math.log(sum + _logGuard);
    }
  }

  // Each mel bin is normalized over the frames.
  for (var mel = 0; mel < melBins; mel++) {
    final offset = mel * frames;
    var mean = 0.0;
    for (var t = 0; t < frames; t++) {
      mean += output[offset + t];
    }
    mean /= frames;
    var squares = 0.0;
    for (var t = 0; t < frames; t++) {
      final d = output[offset + t] - mean;
      squares += d * d;
    }
    final std = math.sqrt(squares / math.max(frames - 1, 1)) + _stdGuard;
    for (var t = 0; t < frames; t++) {
      output[offset + t] = (output[offset + t] - mean) / std;
    }
  }
  return output;
}

final class _Tables {
  _Tables._(int melBins)
    : filterStart = Int32List(melBins),
      filterWeights = List<Float64List>.filled(melBins, Float64List(0)) {
    // torch.hann_window(400, periodic=False), centered in the 512 samples.
    const offset = (_fftSize - _windowLength) ~/ 2;
    for (var n = 0; n < _windowLength; n++) {
      window[offset + n] =
          0.5 - 0.5 * math.cos(2 * math.pi * n / (_windowLength - 1));
    }
    _buildMelFilters(melBins);
  }

  static final _byBins = <int, _Tables>{};
  static _Tables forBins(int melBins) =>
      _byBins[melBins] ??= _Tables._(melBins);

  final window = Float64List(_fftSize);
  final Int32List filterStart;
  final List<Float64List> filterWeights;

  /// librosa.filters.mel(sr=16000, n_fft=512, n_mels=melBins, fmin=0,
  /// fmax=8000, htk=False, norm='slaney').
  void _buildMelFilters(int melBins) {
    final high = _hzToMel(nemoAsrSampleRate / 2);
    final points = List<double>.generate(
      melBins + 2,
      (i) => _melToHz(high * i / (melBins + 1)),
    );
    for (var mel = 0; mel < melBins; mel++) {
      final left = points[mel];
      final center = points[mel + 1];
      final right = points[mel + 2];
      final norm = 2.0 / (right - left);
      final weights = <double>[];
      var start = -1;
      for (var k = 0; k < _bins; k++) {
        final f = k * (nemoAsrSampleRate / 2) / (_bins - 1);
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

/// Power spectrum of one windowed 512-sample frame.
///
/// It packs the even and odd samples into one 256-point complex FFT and
/// splits the result into the 257 bins of the real 512-point FFT.
final class _Fft512 {
  _Fft512() {
    for (var i = 0; i < _fftSize; i++) {
      _cos[i] = math.cos(-2 * math.pi * i / _fftSize);
      _sin[i] = math.sin(-2 * math.pi * i / _fftSize);
    }
    for (var i = 0; i < _n; i++) {
      var r = 0;
      for (var b = 0, v = i; b < 8; b++, v >>= 1) {
        r = (r << 1) | (v & 1);
      }
      _reversed[i] = r;
    }
  }

  static const _n = _fftSize ~/ 2;
  final _cos = Float64List(_fftSize);
  final _sin = Float64List(_fftSize);
  final _reversed = Int32List(_n);
  final _re = Float64List(_n);
  final _im = Float64List(_n);

  void power(
    Float64List signal,
    int offset,
    Float64List window,
    Float64List out,
  ) {
    for (var n = 0; n < _n; n++) {
      final j = _reversed[n];
      _re[j] = signal[offset + 2 * n] * window[2 * n];
      _im[j] = signal[offset + 2 * n + 1] * window[2 * n + 1];
    }
    // Iterative radix-2 FFT. Twiddles for size m are W512^(j·512/m).
    for (var m = 2; m <= _n; m <<= 1) {
      final half = m >> 1;
      final step = _fftSize ~/ m;
      for (var k = 0; k < _n; k += m) {
        for (var j = 0; j < half; j++) {
          final wRe = _cos[j * step];
          final wIm = _sin[j * step];
          final a = k + j;
          final b = a + half;
          final bRe = _re[b] * wRe - _im[b] * wIm;
          final bIm = _re[b] * wIm + _im[b] * wRe;
          _re[b] = _re[a] - bRe;
          _im[b] = _im[a] - bIm;
          _re[a] += bRe;
          _im[a] += bIm;
        }
      }
    }
    for (var k = 0; k <= _n; k++) {
      final a = k % _n;
      final b = (_n - k) % _n;
      // E = (Z[k] + conj(Z[N-k])) / 2, O = (Z[k] - conj(Z[N-k])) / 2i.
      final eRe = (_re[a] + _re[b]) / 2;
      final eIm = (_im[a] - _im[b]) / 2;
      final oRe = (_im[a] + _im[b]) / 2;
      final oIm = -(_re[a] - _re[b]) / 2;
      // X[k] = E + W^k O, W = exp(-2πi/512).
      final wRe = k == _n ? -1.0 : _cos[k];
      final wIm = k == _n ? 0.0 : _sin[k];
      final xRe = eRe + wRe * oRe - wIm * oIm;
      final xIm = eIm + wRe * oIm + wIm * oRe;
      out[k] = xRe * xRe + xIm * xIm;
    }
  }
}
