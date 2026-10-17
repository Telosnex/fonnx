// Runs on the VM and in Chrome:
//   flutter test test/models/spacy_hash_test.dart
//   flutter test --platform chrome test/models/spacy_hash_test.dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fonnx/models/kokoro/misaki/spacy_hash.dart';

import 'spacy_hash_refs.dart';

void main() {
  test('MurmurHash64A matches the 64-bit references', () {
    for (final MapEntry(:key, :value) in murmurRefs.entries) {
      expect(spacyHashString(key).hex, value, reason: key);
    }
  });

  test('thinc hash128 matches the 64-bit references', () {
    for (final (hex, seed, keys) in hash128Refs) {
      expect(thincHash128(U64.parse(hex), seed), keys, reason: '$hex/$seed');
    }
  });

  test('U64 arithmetic wraps at 2^64', () {
    const max = U64(0xFFFFFFFF, 0xFFFFFFFF);
    expect((max + const U64(0, 1)).hex, '0000000000000000');
    expect((max * max).hex, '0000000000000001');
    expect((U64.parse('8000000000000000') >>> 63).hex, '0000000000000001');
    expect((U64.parse('0000000000000001') << 63).hex, '8000000000000000');
    expect((U64.parse('0123456789abcdef') << 4).hex, '123456789abcdef0');
    expect((U64.parse('0123456789abcdef') >>> 36).hex, '0000000000123456');
    expect(U64.from(456).hex, '00000000000001c8');
    expect(utf8.encode('é'), [0xc3, 0xa9]);
  });
}
