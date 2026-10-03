// Independent implementation of the integer mapping that FUTO's ContextLM uses
// for words outside its exact vocabulary. It belongs to the wyhash family but
// is not interchangeable with the current standard wyhash API.
//
// BigInt keeps the 64-bit arithmetic exact on the Web, where Dart integers are
// JavaScript numbers. Golden vectors were produced by the pinned reference
// tool at FUTO swipe-library revision 1b13f2c85d6b347f6ea3fbc4b3aaf01fce42429a.
// No keyboard source is incorporated.
import 'dart:convert';

final _mask = (BigInt.one << 64) - BigInt.one;
final _constants = [
  'a0761d6478bd642f',
  'e7037ed1a0b428db',
  '8ebc6af09c88c6e3',
  '589965cc75374cc3',
].map((s) => BigInt.parse(s, radix: 16)).toList(growable: false);
final _bucketMultipliers = [
  '9e3779b97f4a7c15',
  '517cc1b727220a95',
].map((s) => BigInt.parse(s, radix: 16)).toList(growable: false);

BigInt _mix(BigInt a, BigInt b) {
  final product = (a & _mask) * (b & _mask);
  return (product & _mask) ^ (product >> 64);
}

/// 64-bit ContextLM hash of [word]'s UTF-8 bytes.
BigInt futoContextHash(String word) {
  final bytes = utf8.encode(word);
  final n = bytes.length;
  BigInt read(int start, int width) {
    var value = BigInt.zero;
    for (var i = 0; i < width; i++) {
      value |= BigInt.from(bytes[start + i]) << (8 * i);
    }
    return value;
  }

  var state = _mix(_constants[0], _constants[1]);
  var left = BigInt.zero, right = BigInt.zero;
  if (n <= 16) {
    if (n >= 4) {
      final step = (n ~/ 8) * 4;
      left = (read(0, 4) << 32) | read(step, 4);
      right = (read(n - 4, 4) << 32) | read(n - 4 - step, 4);
    } else if (n > 0) {
      left =
          (BigInt.from(bytes.first) << 16) |
          (BigInt.from(bytes[n ~/ 2]) << 8) |
          BigInt.from(bytes.last);
    }
  } else {
    final lanes = [state, state, state];
    var offset = 0;
    if (n > 48) {
      while (offset + 48 <= n) {
        for (var lane = 0; lane < 3; lane++) {
          final p = offset + lane * 16;
          lanes[lane] = _mix(
            read(p, 8) ^ _constants[lane + 1],
            read(p + 8, 8) ^ lanes[lane],
          );
        }
        offset += 48;
      }
    }
    while (offset + 16 <= n) {
      lanes[0] = _mix(
        read(offset, 8) ^ _constants[1],
        read(offset + 8, 8) ^ lanes[0],
      );
      offset += 16;
    }
    state = n > 48 ? lanes[0] ^ lanes[1] ^ lanes[2] : lanes[0];
    left = read(n - 16, 8);
    right = read(n - 8, 8);
  }
  return _mix(
    _constants[1] ^ BigInt.from(n),
    _mix(left ^ _constants[1], right ^ state),
  );
}

/// The two hashed-embedding rows for [word], each in 0..32767.
List<int> futoContextBuckets(String word) {
  final hash = futoContextHash(word);
  return [
    for (final multiplier in _bucketMultipliers)
      (((hash * multiplier) & _mask) >> 49).toInt(),
  ];
}
