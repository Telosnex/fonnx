import 'dart:typed_data';

import 'package:fonnx/models/magika/magika_model.dart';

import 'magika_none.dart'
    if (dart.library.io) 'magika_native.dart'
    if (dart.library.js) 'magika_web.dart';

export 'magika_model.dart';

abstract class Magika {
  static Magika? _instance;

  static Magika load(String path) {
    _instance ??= getMagika(path);
    return _instance!;
  }

  Future<MagikaType> getType(List<int> bytes);
}

class ModelFeatures {
  List<int> beg;
  List<int> mid;
  List<int> end;
  List<int> get all => [...beg, ...mid, ...end];

  ModelFeatures({required this.beg, required this.mid, required this.end});
}

Future<MagikaType> getTypeFromResultVector(Float32List resultVector) async {
  int maxIndex = 0; // Default to the first index if all else fails.
  double maxValue = -double.infinity;

  // Efficiently find the index of the maximum value in the result vector
  for (int i = 0; i < resultVector.length; i++) {
    if (resultVector[i] > maxValue) {
      maxValue = resultVector[i];
      maxIndex = i;
      // final label = labels[maxIndex];
      // print('Label: $label, Value: $maxValue');
    }
  }
  final label = labels[maxIndex];
  assert(resultVector.length == labels.length,
      'Result vector length does not match the number of labels');
  final matchingType = MagikaType.values.firstWhere(
    (type) => type.targetLabel == label,
    orElse: () {
      return MagikaType.unknown;
    },
  );
  return matchingType;
}

ModelFeatures extractFeaturesFromBytes(Uint8List content,
    {int paddingToken = 256,
    int begSize = 512,
    int midSize = 512,
    int endSize = 512}) {
  List<int> trimBytes(List<int> bytes) {
    int start = 0;
    int end = bytes.length - 1;

    // Identifying leading white spaces/new lines.
    while (start <= end &&
        (bytes[start] == 32 || bytes[start] == 10 || bytes[start] == 13)) {
      start++;
    }

    // Identifying trailing white spaces/new lines.
    while (end >= start &&
        (bytes[end] == 32 || bytes[end] == 10 || bytes[end] == 13)) {
      end--;
    }

    // If there's nothing to trim, return the original bytes; otherwise, return the trimmed subsection.
    return (start <= end) ? bytes.sublist(start, end + 1) : [];
  }

  content = Uint8List.fromList(trimBytes(content));

  List<int> beg = [];
  List<int> mid = [];
  List<int> end = [];

  if (begSize > 0) {
    if (begSize < content.length) {
      beg = List<int>.filled(begSize, 0);
      for (int i = 0; i < begSize; i++) {
        beg[i] = content[i];
      }
    } else {
      final paddingSize = begSize - content.length;
      beg = [
        ...content,
        ...List<int>.filled(paddingSize, paddingToken),
      ];
    }
  }
  assert(beg.length == begSize);

  // Middle chunk
  if (midSize > 0) {
    final midIdx = (content.length ~/ 2);
    if (midSize < content.length) {
      final leftIndex = midIdx - (midSize ~/ 2);

      final midSizeIsEven = midSize.isEven;
      final rightIndex = midIdx + (midSize ~/ 2) + (midSizeIsEven ? 0 : 1);
      mid = content.sublist(leftIndex, rightIndex);
    } else {
      final totalPaddingSize = midSize - content.length;
      final leftPaddingSize = totalPaddingSize ~/ 2;
      final paddingIsEven = totalPaddingSize.isEven;
      final rightPaddingSize = leftPaddingSize + (paddingIsEven ? 0 : 1);

      mid = [
        ...List<int>.filled(leftPaddingSize, paddingToken),
        ...content,
        ...List<int>.filled(rightPaddingSize, paddingToken),
      ];
    }
  } else {
    mid = [];
  }
  assert(mid.length == midSize, 'Mid length: ${mid.length}');

  if (endSize > 0) {
    if (endSize < content.length) {
      end = List<int>.filled(endSize, 0);
      for (int i = 0; i < endSize; i++) {
        end[i] = content[content.length - endSize + i];
      }
    } else {
      final paddingSize = endSize - content.length;
      end = [
        ...List<int>.filled(paddingSize, paddingToken),
        ...content,
      ];
    }
  }
  assert(end.length == endSize);

  // Convert lists back to Uint8List
  return ModelFeatures(
    beg: beg,
    mid: mid,
    end: end,
  );
}

final labels = [
  "ai",
  "apk",
  "appleplist",
  "asm",
  "asp",
  "batch",
  "bmp",
  "bzip",
  "c",
  "cab",
  "cat",
  "chm",
  "coff",
  "crx",
  "cs",
  "css",
  "csv",
  "deb",
  "dex",
  "dmg",
  "doc",
  "docx",
  "elf",
  "emf",
  "eml",
  "epub",
  "flac",
  "gif",
  "go",
  "gzip",
  "hlp",
  "html",
  "ico",
  "ini",
  "internetshortcut",
  "iso",
  "jar",
  "java",
  "javabytecode",
  "javascript",
  "jpeg",
  "json",
  "latex",
  "lisp",
  "lnk",
  "m3u",
  "macho",
  "makefile",
  "markdown",
  "mht",
  "mp3",
  "mp4",
  "mscompress",
  "msi",
  "mum",
  "odex",
  "odp",
  "ods",
  "odt",
  "ogg",
  "outlook",
  "pcap",
  "pdf",
  "pebin",
  "pem",
  "perl",
  "php",
  "png",
  "postscript",
  "powershell",
  "ppt",
  "pptx",
  "python",
  "pythonbytecode",
  "rar",
  "rdf",
  "rpm",
  "rst",
  "rtf",
  "ruby",
  "rust",
  "scala",
  "sevenzip",
  "shell",
  "smali",
  "sql",
  "squashfs",
  "svg",
  "swf",
  "symlinktext",
  "tar",
  "tga",
  "tiff",
  "torrent",
  "ttf",
  "txt",
  "unknown",
  "vba",
  "wav",
  "webm",
  "webp",
  "winregistry",
  "wmf",
  "xar",
  "xls",
  "xlsb",
  "xlsx",
  "xml",
  "xpi",
  "xz",
  "yaml",
  "zip",
  "zlibstream"
];
