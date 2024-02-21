import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:fonnx/fonnx.dart';
import 'package:fonnx/models/magika/magika.dart';
import 'package:fonnx/models/magika/magika_isolate.dart';

Magika getMagika(String path) => MagikaNative(path);

class MagikaNative implements Magika {
  final String modelPath;
  final MagikaIsolateManager _isolate = MagikaIsolateManager();

  MagikaNative(this.modelPath);

  Fonnx? _fonnx;

  @override
  Future<MagikaType> getType(List<int> bytes) async {
    await _isolate.start();
    final Float32List resultVector;
    if (!kIsWeb && Platform.environment['FLUTTER_TEST'] == 'true') {
      resultVector = await _isolate.sendInference(modelPath, bytes);
    } else {
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
        case TargetPlatform.iOS:
          resultVector = await _getMagikaResultVectorViaPlatformChannel(bytes);
        case TargetPlatform.linux:
        case TargetPlatform.macOS:
        case TargetPlatform.windows:
          resultVector = await _getMagikaResultVectorViaFfi(bytes);
        case TargetPlatform.fuchsia:
          throw UnimplementedError();
      }
    }
    return _getTypeFromResultVector(resultVector);
  }

  Future<Float32List> _getMagikaResultVectorViaFfi(List<int> bytes) {
    return _isolate.sendInference(modelPath, bytes);
  }

  Future<Float32List> _getMagikaResultVectorViaPlatformChannel(
      List<int> bytes) async {
    final fonnx = _fonnx ??= Fonnx();
    final type = await fonnx.magika(
      modelPath: modelPath,
      bytes: bytes,
    );
    return type;
  }

  Future<MagikaType> _getTypeFromResultVector(Float32List resultVector) async {
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
      (type) => type.label == label,
      orElse: () => MagikaType.unknown,
    );
    return matchingType;
  }
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
