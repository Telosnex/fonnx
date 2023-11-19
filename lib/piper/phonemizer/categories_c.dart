import 'package:fonnx/piper/phonemizer/ucd_h.dart';

UcdCategory ucdLookupCategory(int c) {
  if (c <= 0x00D7FF) { // 000000..00D7FF
    var table = categories_000000_00D7FF[(c - 0x000000) ~/ 256];
    return table[c % 256];
  }
  if (c <= 0x00DFFF) return UcdCategory.cs; // 00D800..00DFFF : Surrogates
  if (c <= 0x00F7FF) return UcdCategory.co; // 00E000..00F7FF : Private Use Area
  if (c <= 0x02FAFF) { // 00F800..02FAFF
    var table = categories_00F800_02FAFF[(c - 0x00F800) ~/ 256];
    return table[c % 256];
  }
  if (c <= 0x0DFFFF) return UcdCategory.cn; // 02FB00..0DFFFF : Unassigned
  if (c <= 0x0E01FF) { // 0E0000..0E01FF
    var table = categories_0E0000_0E01FF[(c - 0x0E0000) ~/ 256];
    return table[c % 256];
  }
  if (c <= 0x0EFFFF) return UcdCategory.cn; // 0E0200..0EFFFF : Unassigned
  if (c <= 0x0FFFFD) return UcdCategory.co; // 0F0000..0FFFFD : Plane 15 Private Use
  if (c <= 0x0FFFFF) return UcdCategory.cn; // 0FFFFE..0FFFFF : Plane 15 Private Use
  if (c <= 0x10FFFD) return UcdCategory.co; // 100000..10FFFD : Plane 16 Private Use
  if (c <= 0x10FFFF) return UcdCategory.cn; // 10FFFE..10FFFF : Plane 16 Private Use
  return UcdCategory.ii; // Invalid Unicode Codepoint
}