import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fonnx/models/futo_swipe/futo_swipe.dart';
import 'package:fonnx/models/futo_swipe/src/futo_swipe_ort_backend.dart';

import '../../tool/futo/bundle.dart';
import '../../tool/futo/sources.dart';

const bundle = 'example/assets/models/futoSwipe';

/// Runs one golden fixture through the shipped native backend.
Future<List<Float32List>> runFixture(
  NativeFutoSwipeOnnxBackend backend,
  Map fixture,
) async {
  final inputs = {
    for (final input in fixture['inputs'] as List)
      input['name'] as String: input['data'] as List,
  };
  Float32List floats(String name) => Float32List.fromList(
    inputs[name]!.map((v) => (v as num).toDouble()).toList(),
  );
  Int32List ints(String name) => Int32List.fromList(inputs[name]!.cast<int>());
  switch (fixture['model']) {
    case 'encoder':
      final output = await backend.runEncoder(
        floats('features'),
        floats('layout_keys'),
        Uint8List.fromList([
          for (final v in inputs['layout_mask']!) v == true ? 1 : 0,
        ]),
      );
      return [output.logEmissions, output.coefficients, output.intention];
    case 'decoder':
      return [await backend.runDecoder(floats('features'))];
    case 'context':
      return [
        await backend.runContext(ints('token_ids'), ints('hash_buckets')),
      ];
  }
  throw StateError('Unknown fixture model ${fixture['model']}');
}

void main() {
  test(
    'complete FUTO Swipe bundle matches pinned sources and manifest',
    () async {
      await verifyFutoSwipeBundle(Directory(bundle));
      expect(
        File('$bundle/hungry_jellyfish/vocab.txt').readAsLinesSync().last,
        'microfinance',
      );
    },
  );
  for (final path in [
    'LICENSE-FUTO.txt',
    'scoring.json',
    'honorable_sturgeon/metadata.json',
    'magic_macaw/metadata.json',
    'hungry_jellyfish/metadata.json',
    'hungry_jellyfish/vocab.txt',
    'NOTICE.txt',
  ]) {
    test(
      'bundle verifier rejects changed $path even with a changed manifest',
      () async {
        final temp = Directory.systemTemp.createTempSync('fonnx-futo-tamper-');
        try {
          final source = Directory(bundle).absolute;
          for (final entity
              in source.listSync(recursive: true).whereType<File>()) {
            final relative = entity.path.substring(source.path.length + 1);
            File('${temp.path}/$relative').parent.createSync(recursive: true);
            entity.copySync('${temp.path}/$relative');
          }
          final f = File('${temp.path}/$path');
          f.writeAsBytesSync([...f.readAsBytesSync(), 10]);
          final manifest =
              jsonDecode(File('${temp.path}/manifest.json').readAsStringSync())
                  as Map;
          manifest['files'][path] = {
            'sha256': sha256.convert(f.readAsBytesSync()).toString(),
            'bytes': f.lengthSync(),
          };
          File(
            '${temp.path}/manifest.json',
          ).writeAsStringSync(jsonEncode(manifest));
          await expectLater(verifyFutoSwipeBundle(temp), throwsStateError);
        } finally {
          temp.deleteSync(recursive: true);
        }
      },
    );
  }
  test('frozen replay inputs and references match their manifest', () {
    const path = 'test/data/futo_swipe';
    final manifest =
        jsonDecode(File('$path/replay_manifest.json').readAsStringSync())
            as Map;
    final bytes = File('$path/replay.json.gz').readAsBytesSync();
    expect(bytes.length, manifest['fixture']['bytes']);
    expect(sha256.convert(bytes).toString(), manifest['fixture']['sha256']);
    final fixture = jsonDecode(utf8.decode(gzip.decode(bytes))) as Map;
    expect(fixture['modelRevision'], revision);
    expect(fixture['schema'], 2);
    expect((fixture['layout_keys'] as List).length, 128);
    expect((fixture['layout_mask'] as List).length, 64);
    final cases = fixture['cases'] as List;
    expect(cases.length, 1000);
    for (final (i, c) in cases.indexed) {
      expect(c['row'], i);
      expect((c['features'] as List).length, 128);
      expect((c['points'] as List), isNotEmpty);
      expect((c['top3'] as List).length, 3);
      expect((c['features'] as List).every((x) => (x as num).isFinite), isTrue);
    }
    expect(cases.where((c) => c['top3'][0] == c['target']).length, 886);
    expect(
      cases.where((c) => (c['top3'] as List).contains(c['target'])).length,
      914,
    );
  });
  final fixtures =
      jsonDecode(
            utf8.decode(
              gzip.decode(
                File('test/data/futo_swipe/goldens.json.gz').readAsBytesSync(),
              ),
            ),
          )
          as List;
  for (final fixture in fixtures) {
    test(
      '${fixture['model']}: ${fixture['label']} is within ExecuTorch golden tolerances',
      () async {
        final outputs = fixture['outputs'] as List;
        final backend = NativeFutoSwipeOnnxBackend(
          FutoSwipeBundle.fromDirectory(bundle),
        );
        final List<Float32List> result;
        try {
          result = await runFixture(backend, fixture as Map);
        } finally {
          await backend.close();
        }
        for (var i = 0; i < outputs.length; i++) {
          final expected = outputs[i]['data'] as List;
          final actual = result[i];
          expect(actual.length, expected.length);
          for (var j = 0; j < actual.length; j++) {
            final value = (expected[j] as num).toDouble();
            // A float32 ULP near intention=1 changes log(1-intention).
            // The 1000-swipe replay measures up to 0.405 in the blank log score.
            final saturatedBlank =
                fixture['model'] == 'encoder' &&
                outputs[i]['name'] == 'log_emissions' &&
                j % 65 == 64 &&
                value < -11;
            final encoderCoefficient =
                fixture['model'] == 'encoder' &&
                outputs[i]['name'] == 'coefficients';
            final tolerance = saturatedBlank
                ? 0.42
                : encoderCoefficient
                ? 5e-4 * (1 + value.abs())
                : 1e-4 + value.abs() * 1e-4;
            if (!actual[j].isFinite || (actual[j] - value).abs() > tolerance) {
              fail(
                '${fixture['label']} ${outputs[i]['name']}[$j]: ${actual[j]} vs $value (tolerance $tolerance)',
              );
            }
          }
        }
      },
    );
  }
  test(
    'four complete embedding tables match ExecuTorch byte for byte',
    () async {
      final expected =
          jsonDecode(
                File(
                  'test/data/futo_swipe/embedding_hashes.json',
                ).readAsStringSync(),
              )
              as Map;
      final backend = NativeFutoSwipeOnnxBackend(
        FutoSwipeBundle.fromDirectory(bundle),
      );
      try {
        final tables = await backend.loadEmbeddings();
        final actual = {
          'exact_embeddings': tables.exactEmbeddings,
          'exact_biases': tables.exactBiases,
          'hashed_embeddings': tables.hashedEmbeddings,
          'hashed_biases': tables.hashedBiases,
        };
        expect(actual.keys.toSet(), expected.keys.toSet());
        for (final entry in actual.entries) {
          expect(
            sha256.convert(entry.value.buffer.asUint8List()).toString(),
            expected[entry.key],
          );
        }
      } finally {
        await backend.close();
      }
    },
  );
}
