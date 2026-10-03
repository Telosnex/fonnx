import 'dart:math' as math;
import 'dart:typed_data';

import '../futo_swipe_types.dart';

/// Converts a touch trace to the encoder's `features` input, `[2, 64]`.
///
/// This reproduces the NumPy preprocessing used for the published validation:
/// linear interpolation in time to about 60 Hz, then by index to 64 samples.
/// A trace with no duration skips the 60 Hz stage. The arithmetic follows
/// `numpy.linspace` and `numpy.interp` so float32 results match exactly.
Float32List resampleFutoTrace(List<FutoSwipePoint> trace) {
  final count = trace.length;
  final origin = trace.first.time.inMicroseconds;
  final times = Float64List(count);
  final xs = Float64List(count);
  final ys = Float64List(count);
  for (var i = 0; i < count; i++) {
    times[i] = (trace[i].time.inMicroseconds - origin) / 1000;
    xs[i] = trace[i].x;
    ys[i] = trace[i].y;
  }

  var stageX = xs;
  var stageY = ys;
  final duration = times[count - 1];
  if (duration > 1e-3) {
    final samples = math.max(2, _roundHalfEven(duration / (1000 / 60)) + 1);
    final grid = _linspace(0, duration, samples);
    stageX = _interp(grid, times, xs);
    stageY = _interp(grid, times, ys);
  }

  final positions = Float64List(stageX.length);
  for (var i = 0; i < positions.length; i++) {
    positions[i] = i.toDouble();
  }
  final index = _linspace(
    0,
    (stageX.length - 1).toDouble(),
    futoSwipeTraceSamples,
  );
  final x = _interp(index, positions, stageX);
  final y = _interp(index, positions, stageY);
  return Float32List(futoSwipeTraceSamples * 2)
    ..setAll(0, x)
    ..setAll(futoSwipeTraceSamples, y);
}

/// Python's `round`: halves go to the even integer.
int _roundHalfEven(double value) {
  final floor = value.floorToDouble();
  final fraction = value - floor;
  if (fraction > 0.5) return floor.toInt() + 1;
  if (fraction < 0.5) return floor.toInt();
  return floor.toInt().isEven ? floor.toInt() : floor.toInt() + 1;
}

/// `numpy.linspace(start, stop, count)` with an endpoint, for count >= 2.
Float64List _linspace(double start, double stop, int count) {
  final divisions = count - 1;
  final delta = stop - start;
  final step = delta / divisions;
  final result = Float64List(count);
  for (var i = 0; i < count; i++) {
    result[i] = (step == 0 ? i / divisions * delta : i * step) + start;
  }
  result[count - 1] = stop;
  return result;
}

/// `numpy.interp(x, xp, fp)` for finite, non-decreasing [xp].
///
/// Repeated sample times select the last sample at that time, as NumPy does.
Float64List _interp(Float64List x, Float64List xp, Float64List fp) {
  final last = xp.length - 1;
  final result = Float64List(x.length);
  var j = 0;
  for (var i = 0; i < x.length; i++) {
    final value = x[i];
    if (value < xp[0]) {
      result[i] = fp[0];
      continue;
    }
    if (value > xp[last]) {
      result[i] = fp[last];
      continue;
    }
    // Largest j with xp[j] <= value. Queries are sorted, so j only advances.
    if (xp[j] > value) j = 0;
    while (j < last && xp[j + 1] <= value) {
      j++;
    }
    if (j == last || xp[j] == value) {
      result[i] = fp[j];
    } else {
      final slope = (fp[j + 1] - fp[j]) / (xp[j + 1] - xp[j]);
      result[i] = slope * (value - xp[j]) + fp[j];
    }
  }
  return result;
}
