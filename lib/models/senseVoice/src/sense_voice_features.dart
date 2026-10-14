import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fonnx/src/power_spectrum.dart';

const senseVoiceSampleRate = 16000;

/// The width of one model input frame: 7 stacked frames of 80 mel bins.
const senseVoiceFeatureWidth = _stack * _melBins;

const _melBins = 80;
const _frameLength = 400;
const _hop = 160;
const _fftSize = 512;
const _preemphasis = 0.97;
const _stack = 7;
const _stackShift = 6;

/// The number of model input frames for [samples] samples.
int senseVoiceFrames(int samples) {
  final fbank = _fbankFrames(samples);
  return fbank == 0 ? 0 : 1 + (fbank - 1) ~/ _stackShift;
}

int _fbankFrames(int samples) =>
    samples < _frameLength ? 0 : 1 + (samples - _frameLength) ~/ _hop;

/// The input `x` of SenseVoice Small for [samples] in [-1, 1]: frames ×
/// [senseVoiceFeatureWidth] values.
///
/// This is what sherpa-onnx does for the model. Kaldi filter bank features
/// (kaldi-native-fbank): samples scaled to 16-bit range, 25 ms frames every
/// 10 ms without padding, DC offset removed, preemphasis 0.97, a Hamming
/// window, a 512-point power spectrum, 80 HTK mel bins from 20 Hz to 8 kHz,
/// and the log, floored at the float epsilon. Then 7 frames are stacked every
/// 6 frames, repeating the first and last frame at the edges, and each value
/// is normalized with the model's mean and standard deviation.
Float32List senseVoiceFeatures(Float32List samples) {
  final fbankFrames = _fbankFrames(samples.length);
  final fbank = Float32List(fbankFrames * _melBins);
  final tables = _Tables.instance;
  final frame = Float64List(_fftSize);
  final power = Float64List(_fftSize ~/ 2 + 1);
  final spectrum = PowerSpectrum512();
  for (var f = 0; f < fbankFrames; f++) {
    final start = f * _hop;
    var mean = 0.0;
    for (var i = 0; i < _frameLength; i++) {
      frame[i] = samples[start + i] * 32768.0;
      mean += frame[i];
    }
    mean /= _frameLength;
    for (var i = 0; i < _frameLength; i++) {
      frame[i] -= mean;
    }
    for (var i = _frameLength - 1; i > 0; i--) {
      frame[i] -= _preemphasis * frame[i - 1];
    }
    frame[0] -= _preemphasis * frame[0];
    spectrum.power(frame, 0, tables.window, power);
    for (var m = 0; m < _melBins; m++) {
      final first = tables.filterStart[m];
      final weights = tables.filterWeights[m];
      var energy = 0.0;
      for (var k = 0; k < weights.length; k++) {
        energy += weights[k] * power[first + k];
      }
      fbank[f * _melBins + m] = math.log(math.max(energy, _floatEpsilon));
    }
  }

  final frames = senseVoiceFrames(samples.length);
  final output = Float32List(frames * senseVoiceFeatureWidth);
  const left = (_stack - 1) ~/ 2;
  for (var t = 0; t < frames; t++) {
    final center = t * _stackShift;
    for (var j = 0; j < _stack; j++) {
      final source = (center - left + j).clamp(0, fbankFrames - 1);
      final offset = t * senseVoiceFeatureWidth + j * _melBins;
      for (var m = 0; m < _melBins; m++) {
        output[offset + m] =
            (fbank[source * _melBins + m] + _negMean[m]) * _invStddev[m];
      }
    }
  }
  return output;
}

// The float epsilon, 2^-23.
const _floatEpsilon = 1.1920928955078125e-7;

final class _Tables {
  _Tables._() {
    for (var n = 0; n < _frameLength; n++) {
      window[n] = 0.54 - 0.46 * math.cos(2 * math.pi * n / (_frameLength - 1));
    }
    final low = _mel(20);
    final high = _mel(senseVoiceSampleRate / 2);
    final step = (high - low) / (_melBins + 1);
    // Kaldi uses the first 256 FFT bins; the Nyquist bin gets no weight.
    const bins = _fftSize ~/ 2;
    for (var m = 0; m < _melBins; m++) {
      final left = low + m * step;
      final center = left + step;
      final right = center + step;
      final weights = <double>[];
      var start = -1;
      for (var k = 0; k < bins; k++) {
        final mel = _mel(k * senseVoiceSampleRate / _fftSize);
        if (mel <= left || mel >= right) continue;
        final weight = mel <= center
            ? (mel - left) / (center - left)
            : (right - mel) / (right - center);
        if (start < 0) start = k;
        while (start + weights.length < k) {
          weights.add(0);
        }
        weights.add(weight);
      }
      filterStart[m] = math.max(start, 0);
      filterWeights[m] = Float64List.fromList(weights);
    }
  }

  static final instance = _Tables._();

  /// The Hamming window in the first 400 of 512 samples. The rest is zero
  /// padding.
  final window = Float64List(_fftSize);
  final filterStart = Int32List(_melBins);
  final filterWeights = List<Float64List>.filled(_melBins, Float64List(0));

  static double _mel(double hz) => 1127.0 * math.log(1 + hz / 700.0);
}

// The mean and inverse standard deviation of each mel bin, from the metadata
// (neg_mean, inv_stddev) of the sherpa-onnx export. The 7 stacked frames use
// the same 80 values.
const _negMean = <double>[
  -8.311879,
  -8.600912,
  -9.615928,
  -10.43595,
  -11.21292,
  -11.88333,
  -12.36243,
  -12.63706,
  -12.8818,
  -12.83066,
  -12.89103,
  -12.95666,
  -13.19763,
  -13.40598,
  -13.49113,
  -13.5546,
  -13.55639,
  -13.51915,
  -13.68284,
  -13.53289,
  -13.42107,
  -13.65519,
  -13.50713,
  -13.75251,
  -13.76715,
  -13.87408,
  -13.73109,
  -13.70412,
  -13.56073,
  -13.53488,
  -13.54895,
  -13.56228,
  -13.59408,
  -13.62047,
  -13.64198,
  -13.66109,
  -13.62669,
  -13.58297,
  -13.57387,
  -13.4739,
  -13.53063,
  -13.48348,
  -13.61047,
  -13.64716,
  -13.71546,
  -13.79184,
  -13.90614,
  -14.03098,
  -14.18205,
  -14.35881,
  -14.48419,
  -14.60172,
  -14.70591,
  -14.83362,
  -14.92122,
  -15.00622,
  -15.05122,
  -15.03119,
  -14.99028,
  -14.92302,
  -14.86927,
  -14.82691,
  -14.7972,
  -14.76909,
  -14.71356,
  -14.61277,
  -14.51696,
  -14.42252,
  -14.36405,
  -14.30451,
  -14.23161,
  -14.19851,
  -14.16633,
  -14.15649,
  -14.10504,
  -13.99518,
  -13.79562,
  -13.3996,
  -12.7767,
  -11.71208,
];

const _invStddev = <double>[
  0.155775,
  0.154484,
  0.1527379,
  0.1518718,
  0.1506028,
  0.1489256,
  0.147067,
  0.1447061,
  0.1436307,
  0.1443568,
  0.1451849,
  0.1455157,
  0.1452821,
  0.1445717,
  0.1439195,
  0.1435867,
  0.1436018,
  0.1438781,
  0.1442086,
  0.1448844,
  0.1454756,
  0.145663,
  0.146268,
  0.1467386,
  0.1472724,
  0.147664,
  0.1480913,
  0.1483739,
  0.1488841,
  0.1493636,
  0.1497088,
  0.1500379,
  0.1502916,
  0.1505389,
  0.1506787,
  0.1507102,
  0.1505992,
  0.1505445,
  0.1505938,
  0.1508133,
  0.1509569,
  0.1512396,
  0.1514625,
  0.1516195,
  0.1516156,
  0.1515561,
  0.1514966,
  0.1513976,
  0.1512612,
  0.151076,
  0.1510596,
  0.1510431,
  0.151077,
  0.1511168,
  0.1511917,
  0.151023,
  0.1508045,
  0.1505885,
  0.1503493,
  0.1502373,
  0.1501726,
  0.1500762,
  0.1500065,
  0.1499782,
  0.150057,
  0.1502658,
  0.150469,
  0.1505335,
  0.1505505,
  0.1505328,
  0.1504275,
  0.1502438,
  0.1499674,
  0.1497118,
  0.1494661,
  0.1493102,
  0.1493681,
  0.1495501,
  0.1499738,
  0.1509654,
];
