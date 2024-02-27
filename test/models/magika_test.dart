// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fonnx/models/magika/magika.dart';
import 'package:fonnx/models/magika/magika_native.dart';

void main() {
  test('Generate config Dart', skip: 'coder generator', () async {
    String path = 'test/data/magika/content_types_config.json';
    File file = File(path);
    final string = await file.readAsString();
    final labelToJsonObject = jsonDecode(string) as Map<String, dynamic>;
    final allTypeGroups = <String>{};
    final allTags = <String>{};
    final labelsInScopeForOutputContentType = <String>{};
    var count = 0;
    for (final label in labels) {
      final object = labelToJsonObject[label];
      final inScopeForOutputContentType =
          object['in_scope_for_output_content_type'] == true;
      if (inScopeForOutputContentType) {
        count++;
        labelsInScopeForOutputContentType.add(label);
      } else {
        continue;
      }

      final group = object['group'];
      allTypeGroups.add(group);
      final tags = (object['tags'] as List<dynamic>).cast<String>();
      allTags.addAll(tags);

      // Are there cases in which model label != target label?
      // If so, what are they? Can we skip one of them?
      //
      // A: A few, and ex. model_target_label is zip but target_label is APK.
      // We know that the model has ex. APK as a specific output, therefore, we
      // don't need model target label.
      final modelLabel = object['model_target_label'];
      final targetLabel = object['target_label'];
      if (modelLabel != targetLabel) {
        // print('Model label: $modelLabel, Target label: $targetLabel');
      }

      // Does the extensions property require a List?
      // A: Yes.
      // What is the range of # of extensions?
      // A: 0 >= extensions
      // 0: examples unclude unknown, zlibstream, macho...
      // 1: trivial
      // 2: examples include asp, c, gzip, html, mp4, ...
      // Therefore we need a list.
      final extensions = (object['extensions'] as List<dynamic>).cast<String>();
      if (extensions.length != 1) {
        // print('$targetLabel has extensions: $extensions');
      }

      // Does every label have a mime type?
      // A: Yes.
      final mimeType = object['mime_type'];
      if (mimeType == null || mimeType is! String || mimeType.isEmpty) {
        // print('$targetLabel has no mime type');
      }
    }
    expect(count, equals(113));
    final sortedTypeGroups = allTypeGroups.toList()..sort();
    final sortedTags = allTags.toList()..sort();
    print('=== TYPE GROUPS ===');
    print(sortedTypeGroups);
    print('=== TAGS ===');
    print(sortedTags);

    final code = StringBuffer();

    code.writeln('enum MagikaGroup {');
    for (final group in sortedTypeGroups) {
      code.writeln('  $group,');
    }
    code.writeln('}');

    code.writeln('enum MagikaTag {');
    for (final tag in sortedTags) {
      code.writeln('  $tag,');
    }
    code.writeln('}');

    code.writeln('enum MagikaType {');
    for (final label in labelsInScopeForOutputContentType) {
      // ex.
      //       ai(
      //   modelIndex: 1,
      //   label: 'ai',
      //   mimetype: 'application/pdf',
      //   description: 'Adobe Illustrator Artwork',
      // ),
      final object = labelToJsonObject[label];
      code.writeln('  $label(');
      code.writeln('    name: \'${object['name']}\',');
      code.writeln('    description: \'${object['description']}\',');
      code.writeln('    mimeType: \'${object['mime_type']}\',');
      code.writeln('    targetLabel: \'${object['target_label']}\',');
      code.writeln('    extensions: {');
      for (final extension in object['extensions']) {
        code.writeln('      \'$extension\',');
      }
      code.writeln('    },');
      code.writeln('    tags: {');
      for (final tag in object['tags']) {
        code.writeln('      MagikaTag.$tag,');
      }
      code.writeln('    },');
      code.writeln('    groups: {');
      code.writeln('      MagikaGroup.${object['group']},');
      code.writeln('    },');
      code.writeln(
          '  )${label == labelsInScopeForOutputContentType.last ? ';' : ','}');
    }
    code.writeln();
    code.write('''
  const MagikaType(
      {required this.name,
      required this.description,
      required this.mimeType,
      required this.targetLabel,
      required this.extensions,
      required this.tags,
      required this.groups,});

  final String name;
  final String description;
  final String mimeType;
  final String targetLabel;
  final Set<String> extensions;
  final Set<MagikaTag> tags;
  final Set<MagikaGroup> groups;
}
''');

    final codeString = code.toString();
    const outputPath = 'test/outputs/magika_model.dart';
    final outputFile = File(outputPath);
    await outputFile.writeAsString(codeString);
  });

  const modelPath = 'example/assets/models/magika/magika.onnx';
  final magika = MagikaNative(modelPath);

  Future<List<int>> getBytes(String path) async {
    String testFilePath = 'test/data/magika/$path';
    File file = File(testFilePath);
    final bytes = await file.readAsBytes();
    // Trim whitespace from the file bytes.
    return extractFeaturesFromBytes(Uint8List.fromList(bytes)).all;
  }

  Future<MagikaType> getType(List<int> bytes) async {
    return magika.getType(bytes);
  }

  test('text formats', skip: 'not needed; lists text formats', () async {
    for (final magikaType in MagikaType.values) {
      if (magikaType.tags.contains(MagikaTag.text)) {
        print(magikaType);
      }
    }
  });

  test('code.asm', () async {
    final bytes = await getBytes('basic/code.asm');
    final type = await getType(bytes);
    expect(type, MagikaType.asm);
  });

  test('code.c', () async {
    final bytes = await getBytes('basic/code.c');
    final type = await getType(bytes);
    expect(type, MagikaType.c);
  });

  test('code.css', () async {
    final bytes = await getBytes('basic/code.css');
    final type = await getType(bytes);
    expect(type, MagikaType.css);
  });

  test('code.js', () async {
    final bytes = await getBytes('basic/code.js');
    final type = await getType(bytes);
    expect(type, MagikaType.javascript);
  });

  test('code.py', () async {
    final bytes = await getBytes('basic/code.py');
    final type = await getType(bytes);
    expect(type, MagikaType.python);
  });

  test('code.rs', () async {
    final bytes = await getBytes('basic/code.rs');
    final type = await getType(bytes);
    expect(type, MagikaType.rust);
  });

  test('code.smali', () async {
    final bytes = await getBytes('basic/code.smali');
    final type = await getType(bytes);
    expect(type, MagikaType.smali);
  });

  test('doc.docx', () async {
    final bytes = await getBytes('basic/doc.docx');
    final type = await getType(bytes);
    expect(type, MagikaType.docx);
  });

  test('doc.epub', () async {
    final bytes = await getBytes('basic/doc.epub');
    final type = await getType(bytes);
    expect(type, MagikaType.epub);
  });

  test('doc.html', () async {
    final bytes = await getBytes('basic/doc.html');
    final type = await getType(bytes);
    expect(type, MagikaType.html);
  });

  test('doc.ini', () async {
    final bytes = await getBytes('basic/doc.ini');
    final type = await getType(bytes);
    expect(type, MagikaType.ini);
  });

  test('doc.json', () async {
    final bytes = await getBytes('basic/doc.json');
    final type = await getType(bytes);
    expect(type, MagikaType.json);
  });

  test('doc.odt', () async {
    final bytes = await getBytes('basic/doc.odt');
    final type = await getType(bytes);
    expect(type, MagikaType.odt);
  });

  test('doc.pem', () async {
    final bytes = await getBytes('basic/doc.pem');
    final type = await getType(bytes);
    expect(type, MagikaType.pem);
  });

  test('doc.pub', () async {
    final bytes = await getBytes('basic/doc.pub');
    final type = await getType(bytes);
    expect(type, MagikaType.pem);
  });

  test('doc.rtf', () async {
    final bytes = await getBytes('basic/doc.rtf');
    final type = await getType(bytes);
    expect(type, MagikaType.rtf);
  });

  test('7-zip.7z', () async {
    final bytes = await getBytes('mitra/7-zip.7z');
    final type = await getType(bytes);
    expect(type, MagikaType.sevenzip);
  });

  test('bmp.bmp', () async {
    final bytes = await getBytes('mitra/bmp.bmp');
    final type = await getType(bytes);
    expect(type, MagikaType.bmp);
  });

  test('bzip2.bz2', () async {
    final bytes = await getBytes('mitra/bzip2.bz2');
    final type = await getType(bytes);
    expect(type, MagikaType.bzip);
  });

  test('cab.cab', () async {
    final bytes = await getBytes('mitra/cab.cab');
    final type = await getType(bytes);
    expect(type, MagikaType.cab);
  });

  test('elf.elf', () async {
    final bytes = await getBytes('mitra/elf.elf');
    final type = await getType(bytes);
    expect(type, MagikaType.elf);
  });

  test('elf64.elf', () async {
    final bytes = await getBytes('mitra/elf64.elf');
    final type = await getType(bytes);
    expect(type, MagikaType.elf);
  });

  test('flac.flac', () async {
    final bytes = await getBytes('mitra/flac.flac');
    final type = await getType(bytes);
    expect(type, MagikaType.flac);
  });

  test('gif87.gif', () async {
    final bytes = await getBytes('mitra/gif87.gif');
    final type = await getType(bytes);
    expect(type, MagikaType.gif);
  });

  test('gif89.gif', () async {
    final bytes = await getBytes('mitra/gif89.gif');
    final type = await getType(bytes);
    expect(type, MagikaType.gif);
  });

  test('gzip.gz', () async {
    final bytes = await getBytes('mitra/gzip.gz');
    final type = await getType(bytes);
    expect(type, MagikaType.gzip);
  });

  test('hello-world.xar', () async {
    final bytes = await getBytes('mitra/hello-world.xar');
    final type = await getType(bytes);
    expect(type, MagikaType.xar);
  });

  test('html.htm', () async {
    final bytes = await getBytes('mitra/html.htm');
    final type = await getType(bytes);
    expect(type, MagikaType.html);
  });

  test('ico.ico', () async {
    final bytes = await getBytes('mitra/ico.ico');
    final type = await getType(bytes);
    expect(type, MagikaType.ico);
  });

  test('id3v1.mp3', () async {
    final bytes = await getBytes('mitra/id3v1.mp3');
    final type = await getType(bytes);
    expect(type, MagikaType.mp3);
  });

  test('id3v2.mp3', () async {
    final bytes = await getBytes('mitra/id3v2.mp3');
    final type = await getType(bytes);
    expect(type, MagikaType.mp3);
  });

  test('iso.iso', () async {
    final bytes = await getBytes('mitra/iso.iso');
    final type = await getType(bytes);
    expect(type, MagikaType.iso);
  });

  test('java.class', () async {
    final bytes = await getBytes('mitra/java.class');
    final type = await getType(bytes);
    expect(type, MagikaType.javabytecode);
  });

  test('jpg.jpg', () async {
    final bytes = await getBytes('mitra/jpg.jpg');
    final type = await getType(bytes);
    expect(type, MagikaType.jpeg);
  });

  test('mini.bplist', () async {
    final bytes = await getBytes('mitra/mini.bplist');
    final type = await getType(bytes);
    expect(type, MagikaType.appleplist);
  });

  test('mini.plist', () async {
    final bytes = await getBytes('mitra/mini.plist');
    final type = await getType(bytes);
    expect(type, MagikaType.appleplist);
  });

  test('mini.xar', () async {
    final bytes = await getBytes('mitra/mini.xar');
    final type = await getType(bytes);
    expect(type, MagikaType.xar);
  });

  test('mp4.mp4', () async {
    final bytes = await getBytes('mitra/mp4.mp4');
    final type = await getType(bytes);
    expect(type, MagikaType.mp4);
  });

  test('pcap.pcap', () async {
    final bytes = await getBytes('mitra/pcap.pcap');
    final type = await getType(bytes);
    expect(type, MagikaType.pcap);
  });

  test('pcapng.pcapng', () async {
    final bytes = await getBytes('mitra/pcapng.pcapng');
    final type = await getType(bytes);
    expect(type, MagikaType.pcap);
  });

  test('pdf.pdf', () async {
    final bytes = await getBytes('mitra/pdf.pdf');
    final type = await getType(bytes);
    expect(type, MagikaType.pdf);
  });

  test('pe32.exe', () async {
    final bytes = await getBytes('mitra/pe32.exe');
    final type = await getType(bytes);
    expect(type, MagikaType.pebin);
  });

  test('pe64.exe', () async {
    final bytes = await getBytes('mitra/pe64.exe');
    final type = await getType(bytes);
    expect(type, MagikaType.pebin);
  });

  test('php.php', () async {
    final bytes = await getBytes('mitra/php.php');
    final type = await getType(bytes);
    expect(type, MagikaType.php);
  });

  test('png.png', () async {
    final bytes = await getBytes('mitra/png.png');
    final type = await getType(bytes);
    expect(type, MagikaType.png);
  });

  test('qt.mov', () async {
    final bytes = await getBytes('mitra/qt.mov');
    final type = await getType(bytes);
    expect(type, MagikaType.mp4);
  });

  test('rar5.rar', () async {
    final bytes = await getBytes('mitra/rar5.rar');
    final type = await getType(bytes);
    expect(type, MagikaType.rar);
  });

  test('rich.rtf', () async {
    final bytes = await getBytes('mitra/rich.rtf');
    final type = await getType(bytes);
    expect(type, MagikaType.rtf);
  });

  test('tar.tar', () async {
    final bytes = await getBytes('mitra/tar.tar');
    final type = await getType(bytes);
    expect(type, MagikaType.tar);
  });

  test('tiff-be.tif', () async {
    final bytes = await getBytes('mitra/tiff-be.tif');
    final type = await getType(bytes);
    expect(type, MagikaType.tiff);
  });

  test('tiff-le.tif', () async {
    final bytes = await getBytes('mitra/tiff-le.tif');
    final type = await getType(bytes);
    expect(type, MagikaType.tiff);
  });

  test('tiny.flac', () async {
    final bytes = await getBytes('mitra/tiny.flac');
    final type = await getType(bytes);
    expect(type, MagikaType.flac);
  });

  test('vorbis.ogg', () async {
    final bytes = await getBytes('mitra/vorbis.ogg');
    final type = await getType(bytes);
    expect(type, MagikaType.ogg);
  });

  test('webm.webm', () async {
    final bytes = await getBytes('mitra/webm.webm');
    final type = await getType(bytes);
    expect(type, MagikaType.webm);
  });

  test('webp.webp', () async {
    final bytes = await getBytes('mitra/webp.webp');
    final type = await getType(bytes);
    expect(type, MagikaType.webp);
  });

  test('webpl.webp', () async {
    final bytes = await getBytes('mitra/webpl.webp');
    final type = await getType(bytes);
    expect(type, MagikaType.webp);
  });

  test('zip.zip', () async {
    final bytes = await getBytes('mitra/zip.zip');
    final type = await getType(bytes);
    expect(type, MagikaType.zip);
  });

  test('xz.xz', () async {
    final bytes = await getBytes('mitra/xz.xz');
    final type = await getType(bytes);
    expect(type, MagikaType.xz);
  });
}
