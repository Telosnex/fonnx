import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fonnx/models/magika/magika.dart';

import 'package:fonnx_example/padding.dart';
import 'dart:async';
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:path/path.dart' as path;

class MagikaWidget extends StatefulWidget {
  const MagikaWidget({super.key});

  @override
  State<MagikaWidget> createState() => _MagikaWidgetState();
}

class _MagikaWidgetState extends State<MagikaWidget> {
  List<int>? _fileBytes;
  String? _magikaResult;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        heightPadding,
        Text(
          'Magika',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const Text(
            '1 MB model detects 113 types of documents from 1.5 KB. By Google.'),
        heightPadding,
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            ElevatedButton(
              onPressed: () async {
                final bytes = await _pickFileBytes();
                if (bytes != null) {
                  setState(() {
                    _fileBytes = bytes;
                  });
                }
              },
              child: const Text('Open File'),
            ),
            if (_fileBytes != null) widthPadding,
            if (_fileBytes != null)
              const Icon(
                Icons.check,
                color: Colors.green,
              ),
            if (_fileBytes != null) widthPadding,
            if (_fileBytes != null)
              Text('Size: ${_fileBytes?.length ?? 0} bytes'),
          ],
        ),
        if (_fileBytes != null) ...[
          heightPadding,
          ElevatedButton(
            onPressed: () async {
              final path = await getMagikaModelPath('magika.onnx');
              final magika = Magika.load(path);
              final result = await magika.getType(_fileBytes!);
              setState(() {
                _magikaResult = result.toString();
              });
            },
            child: const Text('Run'),
          ),
          if (_magikaResult != null) heightPadding,
          if (_magikaResult != null)
            Text(
              'Result: $_magikaResult',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
        ],
      ],
    );
  }
}

Future<List<int>?> _pickFileBytes() async {
  // Bytes instead of path because of limitation on web.
  FilePickerResult? result = await FilePicker.platform.pickFiles(
    type: FileType.any,
  );
  if (result == null) {
    return null;
  }
  if (result.files.isEmpty) {
    return null;
  }
  if (!kIsWeb && result.files.first.bytes == null) {
    final file = File(result.files.first.path!);
    return file.readAsBytes();
  }
  return result.files.first.bytes;
}

Future<String> getMagikaModelPath(String modelFilenameWithExtension) async {
  if (kIsWeb) {
    return 'assets/models/magika/$modelFilenameWithExtension';
  }
  final assetCacheDirectory =
      await path_provider.getApplicationSupportDirectory();
  final modelPath =
      path.join(assetCacheDirectory.path, modelFilenameWithExtension);

  File file = File(modelPath);
  bool fileExists = await file.exists();
  final fileLength = fileExists ? await file.length() : 0;

  // Do not use path package / path.join for paths.
  // After testing on Windows, it appears that asset paths are _always_ Unix style, i.e.
  // use /, but path.join uses \ on Windows.
  final assetPath =
      'assets/models/magika/${path.basename(modelFilenameWithExtension)}';
  final assetByteData = await rootBundle.load(assetPath);
  final assetLength = assetByteData.lengthInBytes;
  final fileSameSize = fileLength == assetLength;
  if (!fileExists || !fileSameSize) {
    debugPrint(
        'Copying model to $modelPath. Why? Either the file does not exist (${!fileExists}), '
        'or it does exist but is not the same size as the one in the assets '
        'directory. (${!fileSameSize})');
    debugPrint('About to get byte data for $modelPath');

    List<int> bytes = assetByteData.buffer.asUint8List(
      assetByteData.offsetInBytes,
      assetByteData.lengthInBytes,
    );
    debugPrint('About to copy model to $modelPath');
    try {
      if (!fileExists) {
        await file.create(recursive: true);
      }
      await file.writeAsBytes(bytes, flush: true);
    } catch (e) {
      debugPrint('Error writing bytes to $modelPath: $e');
      rethrow;
    }
    debugPrint('Copied model to $modelPath');
  }

  return modelPath;
}
