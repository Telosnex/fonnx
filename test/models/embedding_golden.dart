import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ml_linalg/linalg.dart';

/// Runs [embed] with a checked-in input and compares every output component.
///
/// The tolerance allows for small differences between ORT execution providers
/// and SIMD implementations. Re-baseline a golden only after reviewing an
/// intentional model, tokenizer, or runtime change.
Future<void> expectEmbeddingMatchesGolden(
  Future<Vector> Function(String input) embed,
  String goldenPath, {
  double tolerance = 1e-4,
}) async {
  final decoded = jsonDecode(File(goldenPath).readAsStringSync()) as Map;
  final input = decoded['input'] as String;
  final embedding = decoded['embedding'] as List;
  final expected = embedding
      .cast<num>()
      .map((value) => value.toDouble())
      .toList();
  final actual = await embed(input);

  expect(actual, hasLength(expected.length));
  for (var index = 0; index < expected.length; index++) {
    expect(
      actual[index],
      closeTo(expected[index], tolerance),
      reason: 'embedding component $index changed for input "$input"',
    );
  }
}
