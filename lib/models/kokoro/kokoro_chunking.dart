// Ported from Moonshine, commit 234f60faa0eb388b01cdf7e60aca232af37aefda.
// See lib/third_party/moonshine_LICENSE.txt for its MIT notice.
import 'dart:math' as math;
import 'dart:typed_data';

class KokoroChunkPolicy {
  const KokoroChunkPolicy({
    this.firstChunkSeconds = .6,
    this.toleranceSeconds = .2,
    this.crossfadeSeconds = .025,
    this.growth = 2,
    this.padFrames = 8,
  });
  final double firstChunkSeconds, toleranceSeconds, crossfadeSeconds, growth;
  final int padFrames;

  void validate() {
    for (final value in [
      firstChunkSeconds,
      toleranceSeconds,
      crossfadeSeconds,
      growth,
    ]) {
      if (!value.isFinite || value < 0) {
        throw ArgumentError('Invalid chunk policy');
      }
    }
    if (firstChunkSeconds <= 0 || growth < 1 || padFrames < 0) {
      throw ArgumentError('Invalid chunk policy');
    }
  }

  double maxSustainableGrowth(double realtimeCost, {int framesPerSecond = 40}) {
    if (realtimeCost <= 0) return growth;
    final first = math.max(firstChunkSeconds, .001);
    final padding = framesPerSecond > 0
        ? 2 * math.max(0, padFrames) / framesPerSecond
        : 0;
    return math.max(1, (first / realtimeCost - padding) / first);
  }
}

final _float = Float32List(1);
double _f(double value) {
  _float[0] = value;
  return _float[0];
}

Float32List kokoroBoundaryCost(
  List<double> f0,
  List<double> energy,
  int frames,
) {
  if (frames <= 0) return Float32List(0);
  Float32List standardize(List<double> input, bool pitch) {
    final values = Float32List(frames);
    for (var i = 0; i < frames; i++) {
      final v = input.length >= 2 * frames
          ? _f(.5 * _f(input[2 * i] + input[2 * i + 1]))
          : i < input.length
          ? input[i]
          : 0.0;
      values[i] = pitch ? math.min(v, 200) : v.abs();
    }
    final mean = values.fold(0.0, (a, b) => a + b) / frames;
    final spread = math.sqrt(
      values.fold(0.0, (a, b) => a + (b - mean) * (b - mean)) / frames,
    );
    for (var i = 0; i < frames; i++) {
      values[i] = spread < 1e-9 ? 0 : (values[i] - mean) / spread;
    }
    return values;
  }

  final loud = standardize(energy, false), pitch = standardize(f0, true);
  return Float32List.fromList([
    for (var i = 0; i < frames; i++) _f(loud[i] + _f(.5 * pitch[i])),
  ]);
}

/// A slice that starts or ends in a pause decodes noise, and often a short
/// burst (a click). A boundary must have [kokoroSpeechMinFrames] speech frames
/// in the [kokoroSpeechWindow] frames after it, and as many in the
/// [kokoroSpeechWindow] frames before it.
const kokoroSpeechWindow = 8, kokoroSpeechMinFrames = 4;

/// Which frames have speech, from the prosody energy. Prosody energy is about
/// 6 in speech and below 0 in silence.
List<bool> kokoroSpeechFrames(
  List<double> energy,
  int frames, {
  double threshold = 2,
}) => [
  for (var i = 0; i < frames; i++)
    (energy.length >= 2 * frames
            ? .5 * (energy[2 * i] + energy[2 * i + 1])
            : i < energy.length
            ? energy[i]
            : double.negativeInfinity) >
        threshold,
];

/// [speech], if given, keeps every boundary out of pauses. A boundary in a
/// pause moves to where speech is again. Leading and trailing pauses join the
/// first and last slices. This is a change from Moonshine.
List<int> kokoroPlanBoundaries(
  List<double> cost,
  int frames, {
  KokoroChunkPolicy policy = const KokoroChunkPolicy(),
  int framesPerSecond = 40,
  List<bool>? speech,
}) {
  policy.validate();
  if (frames <= 0 || framesPerSecond <= 0) return [0, math.max(frames, 0)];
  if (speech != null && speech.length != frames) {
    throw ArgumentError('speech must have one value per frame');
  }
  int speechIn(int from, int to) {
    var n = 0;
    for (var j = math.max(0, from); j < math.min(frames, to); j++) {
      if (speech![j]) n++;
    }
    return n;
  }

  final inSpeech = speech == null
      ? null
      : List.generate(
          frames,
          (i) =>
              speechIn(i, i + kokoroSpeechWindow) >= kokoroSpeechMinFrames &&
              speechIn(i - kokoroSpeechWindow, i) >= kokoroSpeechMinFrames,
        );
  bool allowed(int i) => inSpeech == null || inSpeech[i];
  final search = math.max(
    0,
    _f(_f(policy.toleranceSeconds) * framesPerSecond).round(),
  );
  var step = math
      .max(1, _f(_f(policy.firstChunkSeconds) * framesPerSecond).round())
      .toDouble();
  var current = 0;
  final boundaries = [0];
  while (true) {
    final nominal = (current + math.max(1, step.round())).toInt();
    if (nominal >= frames) break;
    var next = -1;
    final low = math.max(current + 2, nominal - search).toInt();
    final high = math.min(frames - 2, nominal + search + 1).toInt();
    if (cost.length == frames && high > low) {
      for (var i = low; i < high; i++) {
        if (allowed(i) && (next < 0 || cost[i] < cost[next])) next = i;
      }
    } else if (allowed(nominal)) {
      next = nominal;
    }
    if (next < 0) {
      // The whole search window is a pause: cut where speech starts again.
      for (var i = math.max(low, high); i < frames - 2; i++) {
        if (allowed(i)) {
          next = i;
          break;
        }
      }
    }
    if (next <= current) break;
    boundaries.add(next);
    current = next;
    step *= _f(policy.growth);
  }
  return [...boundaries, frames];
}

class KokoroChunkSpan {
  const KokoroChunkSpan(
    this.decodeFirst,
    this.decodeLast,
    this.keepFirst,
    this.keepLast,
  );
  final int decodeFirst, decodeLast, keepFirst, keepLast;
}

List<KokoroChunkSpan> kokoroPlanSpans(
  List<int> boundaries,
  int frames, {
  KokoroChunkPolicy policy = const KokoroChunkPolicy(),
  int samplesPerFrame = 600,
  int sampleRate = 24000,
}) {
  policy.validate();
  if (boundaries.length < 2 || frames <= 0 || samplesPerFrame <= 0) return [];
  final total = frames * samplesPerFrame;
  final half = _f(_f(policy.crossfadeSeconds) * sampleRate).round() ~/ 2;
  return [
    for (var i = 0; i + 1 < boundaries.length; i++)
      (() {
        final first = math.max(0, boundaries[i] * samplesPerFrame - half);
        final last = math.min(
          total,
          boundaries[i + 1] * samplesPerFrame + half,
        );
        return KokoroChunkSpan(
          math.max(0, first ~/ samplesPerFrame - policy.padFrames),
          math.min(
            frames,
            (last + samplesPerFrame - 1) ~/ samplesPerFrame + policy.padFrames,
          ),
          first,
          last,
        );
      })(),
  ];
}

Float32List kokoroCrossfade(
  List<double> previous,
  List<double> piece,
  int overlap,
) {
  final n = math.min(
    math.max(0, overlap),
    math.min(previous.length, piece.length),
  );
  final out = Float32List(previous.length + piece.length - n)
    ..setAll(0, previous);
  for (var i = 0; i < n; i++) {
    final angle = _f(_f(_f((i + .5) / n) * _f(math.pi)) * .5);
    out[previous.length - n + i] = _f(
      _f(previous[previous.length - n + i] * _f(math.cos(angle))) +
          _f(piece[i] * _f(math.sin(angle))),
    );
  }
  out.setRange(previous.length, out.length, piece, n);
  return out;
}

/// Incrementally holds the overlapping tail; emitted samples never repeat.
class KokoroSliceJoiner {
  KokoroSliceJoiner({this.policy = const KokoroChunkPolicy()});
  final KokoroChunkPolicy policy;
  Float32List _carry = Float32List(0);
  Float32List add(List<double> piece, {required bool last}) {
    final joined = kokoroCrossfade(_carry, piece, _carry.length);
    final hold = last
        ? 0
        // kokoroPlanSpans overlaps slices by twice its half crossfade.
        : math.min(
            joined.length,
            _f(_f(policy.crossfadeSeconds) * 24000).round() ~/ 2 * 2,
          );
    _carry = Float32List.fromList(joined.sublist(joined.length - hold));
    return Float32List.sublistView(joined, 0, joined.length - hold);
  }
}

/// Split by Unicode code points as Moonshine's chunk_phonemes does.
List<String> kokoroSplitPhonemes(String phonemes, {int limit = 510}) {
  if (limit < 1) throw ArgumentError.value(limit, 'limit');
  var remaining = phonemes.runes.toList();
  final pieces = <String>[];
  while (remaining.isNotEmpty) {
    var cut = math.min(remaining.length, limit);
    if (remaining.length > limit) {
      final space = remaining.lastIndexOf(32, limit);
      if (space > 0) cut = space;
    }
    final part = String.fromCharCodes(remaining.take(cut)).trim();
    if (part.isNotEmpty) pieces.add(part);
    remaining = remaining.sublist(cut);
    while (remaining.isNotEmpty && remaining.first == 32) {
      remaining.removeAt(0);
    }
  }
  return pieces;
}
