/// spaCy's string hash and thinc's embedding hash, with exact results on the
/// Dart VM and when compiled to JavaScript.
///
/// JavaScript numbers hold integers exactly only up to 2^53, and its bitwise
/// operators use 32 bits. [U64] keeps each value as two 32-bit halves, and
/// multiplies with 16-bit limbs so that no intermediate exceeds 2^53.
library;

import 'dart:convert';

const _two32 = 0x100000000;
const _two16 = 0x10000;
const _mask32 = 0xFFFFFFFF;

/// An unsigned 64-bit integer, as two 32-bit halves.
final class U64 {
  /// [hi] and [lo] must be in 0..2^32-1.
  const U64(this.hi, this.lo);

  /// [value] must be in 0..2^53.
  factory U64.from(int value) => U64(value ~/ _two32, value % _two32);

  /// Parses 16 hexadecimal digits.
  factory U64.parse(String hex) => U64(
    int.parse(hex.substring(0, 8), radix: 16),
    int.parse(hex.substring(8), radix: 16),
  );

  final int hi, lo;

  static const zero = U64(0, 0);

  U64 operator ^(U64 o) => U64((hi ^ o.hi) & _mask32, (lo ^ o.lo) & _mask32);

  U64 operator |(U64 o) => U64((hi | o.hi) & _mask32, (lo | o.lo) & _mask32);

  /// Addition modulo 2^64.
  U64 operator +(U64 o) {
    final low = lo + o.lo;
    final carry = low >= _two32 ? 1 : 0;
    return U64((hi + o.hi + carry) % _two32, low % _two32);
  }

  /// Multiplication modulo 2^64.
  U64 operator *(U64 o) {
    final a0 = lo % _two16, a1 = lo ~/ _two16;
    final a2 = hi % _two16, a3 = hi ~/ _two16;
    final b0 = o.lo % _two16, b1 = o.lo ~/ _two16;
    final b2 = o.hi % _two16, b3 = o.hi ~/ _two16;
    var c = a0 * b0;
    final r0 = c % _two16;
    c = c ~/ _two16 + a0 * b1 + a1 * b0;
    final r1 = c % _two16;
    c = c ~/ _two16 + a0 * b2 + a1 * b1 + a2 * b0;
    final r2 = c % _two16;
    c = c ~/ _two16 + a0 * b3 + a1 * b2 + a2 * b1 + a3 * b0;
    final r3 = c % _two16;
    return U64(r2 + r3 * _two16, r0 + r1 * _two16);
  }

  /// Logical shift right; [n] is in 1..63.
  U64 operator >>>(int n) {
    if (n >= 32) return U64(0, hi >>> (n - 32));
    return U64(hi >>> n, ((lo >>> n) | (hi << (32 - n))) & _mask32);
  }

  /// Shift left modulo 2^64; [n] is in 1..63.
  U64 operator <<(int n) {
    if (n >= 32) return U64((lo << (n - 32)) & _mask32, 0);
    return U64(((hi << n) | (lo >>> (32 - n))) & _mask32, (lo << n) & _mask32);
  }

  /// 16 lowercase hexadecimal digits.
  String get hex =>
      hi.toRadixString(16).padLeft(8, '0') +
      lo.toRadixString(16).padLeft(8, '0');

  @override
  bool operator ==(Object other) =>
      other is U64 && other.hi == hi && other.lo == lo;

  @override
  int get hashCode => Object.hash(hi, lo);

  @override
  String toString() => hex;
}

const _m = U64(0xc6a4a793, 0x5bd1e995);

/// MurmurHash64A of the UTF-8 bytes of [s], seed 1: spaCy's `hash_string`.
U64 spacyHashString(String s) => murmurHash64A(utf8.encode(s));

/// MurmurHash64A of [data] with [seed].
U64 murmurHash64A(List<int> data, {int seed = 1}) {
  const r = 47;
  var h = U64.from(seed) ^ (U64.from(data.length) * _m);
  final n = data.length ~/ 8;
  for (var i = 0; i < n; i++) {
    final o = i * 8;
    var k = U64(
      data[o + 4] |
          data[o + 5] << 8 |
          data[o + 6] << 16 |
          data[o + 7] * 0x1000000,
      data[o] | data[o + 1] << 8 | data[o + 2] << 16 | data[o + 3] * 0x1000000,
    );
    k = k * _m;
    k = k ^ (k >>> r);
    k = k * _m;
    h = h ^ k;
    h = h * _m;
  }
  final tail = data.length & 7;
  if (tail != 0) {
    var hi = 0, lo = 0;
    for (var i = 0; i < tail; i++) {
      final byte = data[n * 8 + i];
      if (i < 4) {
        lo += byte * (1 << (8 * i));
      } else {
        hi += byte * (1 << (8 * (i - 4)));
      }
    }
    h = h ^ U64(hi, lo);
    h = h * _m;
  }
  h = h ^ (h >>> r);
  h = h * _m;
  h = h ^ (h >>> r);
  return h;
}

const _c1 = U64(0x87c37b91, 0x114253d5);
const _c2 = U64(0x4cf5ad43, 0x2745937f);
const _f1 = U64(0xff51afd7, 0xed558ccd);
const _f2 = U64(0xc4ceb9fe, 0x1a85ec53);

U64 _fmix(U64 k) {
  k = k ^ (k >>> 33);
  k = k * _f1;
  k = k ^ (k >>> 33);
  k = k * _f2;
  return k ^ (k >>> 33);
}

/// thinc's `MurmurHash3_x86_128_uint64` of [value]: four 32-bit keys.
List<int> thincHash128(U64 value, int seed) {
  final s = U64.from(seed);
  const eight = U64(0, 8);
  var h1 = value * _c1;
  h1 = (h1 << 31) | (h1 >>> 33);
  h1 = h1 * _c2;
  h1 = h1 ^ s ^ eight;
  var h2 = s ^ eight;
  h1 = h1 + h2;
  h2 = h2 + h1;
  h1 = _fmix(h1);
  h2 = _fmix(h2);
  h1 = h1 + h2;
  h2 = h2 + h1;
  return [h1.lo, h1.hi, h2.lo, h2.hi];
}
