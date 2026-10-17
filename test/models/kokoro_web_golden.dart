import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fonnx/models/kokoro/kokoro.dart';

/// Cases of test/data/goldens/kokoro_web.json. The third has words that
/// only misaki's fallback model can pronounce.
const kokoroWebCases = [
  (
    voice: 'af_heart',
    text: 'I read the book yesterday, and I will read it again tomorrow.',
  ),
  (
    voice: 'bf_emma',
    text:
        "The Dormouse wasn't in the least tired; she'd had tea at half past four.",
  ),
  (
    voice: 'af_heart',
    text: 'Zorbleflax and Quixotrandle snarfed the brillig wugs.',
  ),
];

/// Fixed span growth: the plan of spans does not depend on the measured
/// decode speed, so native and web decode the same spans.
const kokoroWebPolicy = KokoroChunkPolicy(growth: 1);

/// RMS of each 100 ms of [samples].
List<double> kokoroEnvelope(Float32List samples) => [
  for (var o = 0; o < samples.length; o += 2400)
    math.sqrt(
      samples
              .sublist(o, math.min(o + 2400, samples.length))
              .fold(0.0, (s, v) => s + v * v) /
          math.min(2400, samples.length - o),
    ),
];

/// Pearson correlation of two envelopes, over their common length.
double kokoroCorrelation(List<double> a, List<double> b) {
  final n = math.min(a.length, b.length);
  double mean(List<double> x) => x.take(n).fold(0.0, (s, v) => s + v) / n;
  final ma = mean(a), mb = mean(b);
  var ab = 0.0, aa = 0.0, bb = 0.0;
  for (var i = 0; i < n; i++) {
    ab += (a[i] - ma) * (b[i] - mb);
    aa += (a[i] - ma) * (a[i] - ma);
    bb += (b[i] - mb) * (b[i] - mb);
  }
  return ab / math.sqrt(aa * bb);
}
