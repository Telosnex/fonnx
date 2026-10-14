import 'dart:math' as math;
import 'dart:typed_data';

const _fftSize = 512;

/// Power spectrum of one windowed 512-sample frame: 257 bins.
///
/// It packs the even and odd samples into one 256-point complex FFT and
/// splits the result into the 257 bins of the real 512-point FFT.
final class PowerSpectrum512 {
  PowerSpectrum512() {
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

  /// Writes to [out] the power spectrum of the 512 samples of [signal] from
  /// [offset], each multiplied by the same index of [window].
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
