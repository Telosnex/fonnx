// Kokoro first-audio benchmark. Skipped unless KOKORO_BENCH is set:
//   KOKORO_BENCH=1 dart test test/models/kokoro_benchmark_test.dart
//
// Prints one table for the first utterance of each case. "first" is from
// the request (or the first add) to the first chunk. "total" is to the last
// chunk. "rtf" is total / audio; for input rows it includes the wait for
// text. "gap" is the longest silence a player would have, if it started at
// the first chunk and played chunks in order.
//
// Input rows add one word per token at a fixed rate, then one more sentence,
// so the first unit ends when the next word arrives (D3 in ADR 014).
import 'dart:async';
import 'dart:io';
import 'package:test/test.dart';
import 'package:fonnx/models/kokoro/kokoro.dart';

import 'kokoro_stream_test.dart' show bundle;

const _voice = 'af_heart';
const _runs = 5;

const _sentences = {
  5: 'The weather looks great today.',
  15:
      'I checked your calendar, and the meeting with Sam moved to three on '
      'Thursday afternoon.',
  30:
      'I looked through the three reports you sent this morning, and the main '
      'difference is that the second one counts returns as revenue, which '
      'makes its totals twelve percent higher.',
};

/// Text after the first sentence, so D3 sees a next word, as in a reply.
const _next = ' Then the next sentence starts.';

class _Run {
  _Run(this.firstMs, this.totalMs, this.audioMs, this.gapMs);
  final double firstMs, totalMs, audioMs, gapMs;
}

/// Times the first utterance of [audio]. [clock] started at the request.
Future<_Run> _time(Stream<KokoroChunk> audio, Stopwatch clock) async {
  double? first;
  var audioMs = 0.0, gap = 0.0;
  int? firstUtterance;
  await for (final chunk in audio) {
    firstUtterance ??= chunk.utteranceId;
    if (chunk.utteranceId != firstUtterance) break;
    final now = clock.elapsedMicroseconds / 1000;
    first ??= now;
    // The player has played audioMs since the first chunk, if it never waited.
    final late = (now - first) - audioMs;
    if (late > gap) gap = late;
    audioMs += chunk.samples.length / chunk.sampleRate * 1000;
    if (chunk.isFinal) break;
  }
  return _Run(first!, clock.elapsedMicroseconds / 1000, audioMs, gap);
}

Future<_Run> _speak(Kokoro engine, String text) {
  final clock = Stopwatch()..start();
  return _time(engine.speak(text, voice: _voice), clock);
}

/// Adds one word per token at [tokensPerSecond], from the first add.
Future<_Run> _stream(Kokoro engine, String text, int tokensPerSecond) async {
  final input = engine.input(voice: _voice);
  final clock = Stopwatch()..start();
  final timed = _time(input.audio, clock);
  final words = RegExp(r'\S+\s*').allMatches(text).map((m) => m[0]!).toList();
  final period = Duration(microseconds: 1000000 ~/ tokensPerSecond);
  unawaited(() async {
    for (var i = 0; i < words.length; i++) {
      final due = period * i - clock.elapsed;
      if (due > Duration.zero) await Future<void>.delayed(due);
      try {
        input.add(words[i]);
      } on StateError {
        return; // Audio was cancelled after the first utterance.
      }
    }
    await input.close();
  }());
  return timed;
}

double _median(Iterable<double> values) {
  final sorted = values.toList()..sort();
  return sorted[sorted.length ~/ 2];
}

String _row(String label, List<_Run> runs) {
  String f(double v) => v.toStringAsFixed(0).padLeft(6);
  final first = _median(runs.map((r) => r.firstMs));
  final total = _median(runs.map((r) => r.totalMs));
  final audio = _median(runs.map((r) => r.audioMs));
  final rtf = _median(runs.map((r) => r.totalMs / r.audioMs));
  final gap = runs.map((r) => r.gapMs).reduce((a, b) => a > b ? a : b);
  return '${label.padRight(22)}${f(first)}${f(total)}${f(audio)}'
      '${rtf.toStringAsFixed(2).padLeft(7)}${f(gap)}';
}

void main() {
  test(
    'Kokoro first-audio benchmark',
    () async {
      final loadClock = Stopwatch()..start();
      final engine = await Kokoro.load(bundle());
      addTearDown(engine.dispose);
      final loadMs = loadClock.elapsedMilliseconds;
      final cold = await _speak(engine, _sentences[5]!);

      final rows = <String>[];
      for (final MapEntry(key: words, value: sentence) in _sentences.entries) {
        final speak = [
          for (var i = 0; i < _runs; i++) await _speak(engine, sentence),
        ];
        rows.add(_row('speak $words words', speak));
      }
      for (final rate in [20, 50]) {
        for (final MapEntry(key: words, value: sentence)
            in _sentences.entries) {
          final streamed = [
            for (var i = 0; i < _runs; i++)
              await _stream(engine, sentence + _next, rate),
          ];
          rows.add(_row('input $words w @ $rate tok/s', streamed));
        }
      }

      final header =
          '${'case'.padRight(22)}${'first'.padLeft(6)}${'total'.padLeft(6)}'
          '${'audio'.padLeft(6)}${'rtf'.padLeft(7)}${'gap'.padLeft(6)}';
      // ignore: avoid_print
      print(
        [
          'Kokoro benchmark, ${Platform.operatingSystem} '
              '${Platform.operatingSystemVersion}, '
              '${Platform.numberOfProcessors} cores',
          'load ${loadMs}ms; cold 5-word speak: first '
              '${cold.firstMs.toStringAsFixed(0)}ms',
          'median of $_runs runs, ms; gap is the max over runs',
          header,
          ...rows,
        ].join('\n'),
      );
    },
    skip: Platform.environment['KOKORO_BENCH'] == null
        ? 'Set KOKORO_BENCH=1 to run'
        : null,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
