// espeak-ng/src/libespeak-ng/encoding.c

import 'dart:typed_data';

class EspeakNgTextDecoder {
  Uint8List? current;
  Uint8List? end;
  Uint16List? codepage;
  int Function(EspeakNgTextDecoder decoder)? getter;
  EspeakNgTextDecoder(
      {required this.current, required this.end, required this.codepage, this.getter});
}

enum EspeakNgEncoding {
  unknown,
  usAscii,
  iso8859_1,
  iso8859_2,
  iso8859_3,
  iso8859_4,
  iso8859_5,
  iso8859_6,
  iso8859_7,
  iso8859_8,
  iso8859_9,
  iso8859_10,
  iso8859_11,
  // ISO-8859-12 is not a valid encoding, so it is not included here.
  iso8859_13,
  iso8859_14,
  iso8859_15,
  iso8859_16,
  koi8R,
  iscii,
  utf8,
  iso10646Ucs2,
}
