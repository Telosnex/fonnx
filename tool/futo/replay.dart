// Optional, network-enabled end-to-end regression for the public FutoSwipe API.
// flutter test tool/futo/replay.dart --concurrency=1 --reporter expanded
//
// Raw public traces go through FutoSwipe.decode: Dart resampling, native ONNX
// Runtime, and lexicon search. Results are compared with frozen ExecuTorch
// top-three goldens. ExecuTorch is not rerun.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fonnx/fonnx.dart';

import 'bundle.dart';
import 'sources.dart';

Future<Uint8List> pinnedLexicon(HttpClient client, Map source) async {
  final response = await (await client.getUrl(
    Uri.parse(source['url'] as String),
  )).close();
  if (response.statusCode != 200) {
    throw HttpException('Lexicon HTTP ${response.statusCode}');
  }
  final builder = await response.fold(
    BytesBuilder(copy: false),
    (b, c) => b..add(c),
  );
  final bytes = builder.takeBytes();
  if (bytes.length != source['bytes'] ||
      sha256.convert(bytes).toString() != source['sha256']) {
    throw StateError('Lexicon hash mismatch: ${source['url']}');
  }
  return bytes;
}

/// The validated lexicon: whole words of letters only, in source order.
final _validatedWord = RegExp(r'^[A-Za-z]+$');

void main() {
  test(
    '1000 raw swipes through FutoSwipe preserve frozen ExecuTorch top-three',
    () async {
      final bundle = Directory('example/assets/models/futoSwipe');
      await verifyFutoSwipeBundle(bundle);
      const dataPath = 'test/data/futo_swipe';
      final manifest =
          jsonDecode(File('$dataPath/replay_manifest.json').readAsStringSync())
              as Map;
      final bytes = File('$dataPath/replay.json.gz').readAsBytesSync();
      expect(bytes.length, manifest['fixture']['bytes']);
      expect(sha256.convert(bytes).toString(), manifest['fixture']['sha256']);
      final fixture = jsonDecode(utf8.decode(gzip.decode(bytes))) as Map;
      expect(fixture['modelRevision'], revision);
      final rows = fixture['cases'] as List;
      expect(rows.length, 1000);

      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 30);
      FutoSwipe? swipe;
      try {
        final lexicon = <FutoSwipeWord>[
          for (final word in File(
            '${bundle.path}/hungry_jellyfish/vocab.txt',
          ).readAsLinesSync())
            if (_validatedWord.hasMatch(word)) FutoSwipeWord(word),
        ];
        final sources = manifest['lexicons'] as Map;
        final spelling = utf8.decode(
          await pinnedLexicon(client, sources['esdb'] as Map),
        );
        for (final word in const LineSplitter().convert(spelling)) {
          if (_validatedWord.hasMatch(word)) lexicon.add(FutoSwipeWord(word));
        }
        final frequencies = utf8.decode(
          gzip.decode(await pinnedLexicon(client, sources['aosp'] as Map)),
        );
        final entry = RegExp(r'^\s+word=(.*),f=(\d+),');
        for (final line in const LineSplitter().convert(frequencies)) {
          final m = entry.firstMatch(line);
          if (m != null &&
              !line.contains('blacklist') &&
              _validatedWord.hasMatch(m[1]!)) {
            lexicon.add(FutoSwipeWord(m[1]!, frequency: int.parse(m[2]!)));
          }
        }
        swipe = await FutoSwipe.load(
          bundle: FutoSwipeBundle.fromDirectory(bundle.path),
          lexicon: lexicon,
          includeModelVocabulary: false,
        );

        var sameFirst = 0, sameThree = 0;
        var referenceTop1 = 0, referenceTop3 = 0;
        var actualTop1 = 0, actualTop3 = 0;
        final differences = <Map<String, dynamic>>[];
        final clock = Stopwatch();
        final latencies = <int>[];
        for (final (index, row) in rows.indexed) {
          final trace = [
            for (final p in (row['points'] as List).cast<List>())
              FutoSwipePoint(
                (p[1] as num).toDouble(),
                (p[2] as num).toDouble(),
                Duration(milliseconds: p[0] as int),
              ),
          ];
          clock
            ..reset()
            ..start();
          final results = await swipe.decode(trace);
          latencies.add(clock.elapsedMicroseconds);
          final prediction = [for (final r in results) r.searchKey];
          final reference = (row['top3'] as List).cast<String>();
          final target = row['target'];
          if (reference.isNotEmpty && reference.first == target) {
            referenceTop1++;
          }
          if (reference.contains(target)) referenceTop3++;
          if (prediction.isNotEmpty && prediction.first == target) {
            actualTop1++;
          }
          if (prediction.contains(target)) actualTop3++;
          if (reference.isNotEmpty &&
              prediction.isNotEmpty &&
              reference.first == prediction.first) {
            sameFirst++;
          }
          if (jsonEncode(reference) == jsonEncode(prediction)) {
            sameThree++;
          } else {
            differences.add({
              'row': index,
              'reference': reference,
              'actual': prediction,
            });
          }
          if ((index + 1) % 100 == 0) {
            stdout.writeln('Replayed ${index + 1}/${rows.length} swipes');
          }
        }
        latencies.sort();
        double ms(double p) =>
            latencies[(latencies.length * p).floor().clamp(
              0,
              latencies.length - 1,
            )] /
            1000;
        final report = {
          'count': rows.length,
          'api': 'FutoSwipe.decode from raw trace points',
          'context': false,
          'beam': 300,
          'swipeableLexicon': swipe.lexiconSize,
          'sameFirst': sameFirst,
          'sameTopThreeOrdered': sameThree,
          'etTop1': referenceTop1,
          'ortTop1': actualTop1,
          'etTop3': referenceTop3,
          'ortTop3': actualTop3,
          'decodeMilliseconds': {'p50': ms(0.5), 'p95': ms(0.95)},
          'differences': differences,
        };
        stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
        expect(referenceTop1, 886);
        expect(referenceTop3, 914);
        expect(differences, isEmpty);
        expect(sameFirst, 1000);
        expect(sameThree, 1000);
      } finally {
        await swipe?.close();
        client.close(force: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
