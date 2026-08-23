import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fonnx/models/msmarcoMiniLmL6V3/msmarco_mini_lm_l6_v3.dart';
import 'package:fonnx_example/padding.dart';
import 'dart:async';
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:path/path.dart' as path;

class MsmarcoMiniLmL6V3Widget extends StatefulWidget {
  const MsmarcoMiniLmL6V3Widget({super.key});

  @override
  State<MsmarcoMiniLmL6V3Widget> createState() =>
      _MsmarcoMiniLmL6V3WidgetState();
}

class _MsmarcoMiniLmL6V3WidgetState extends State<MsmarcoMiniLmL6V3Widget> {
  String? _speedTestResult;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        heightPadding,
        Text(
          'MSMARCO MiniLM L6 V3',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const Text(
            '23 MB model can convert text to a 384-dimensional vector. By Microsoft.\nFor asymmetric search: matching a query to documents with the answer in them.'),
        heightPadding,
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            ElevatedButton(
              onPressed: _runSpeedTest,
              child: const Text('Test Speed'),
            ),
            widthPadding,
            if (_speedTestResult != null) Text(_speedTestResult!),
          ],
        ),
      ],
    );
  }

  void _runSpeedTest() async {
    final string = await rootBundle.loadString('assets/text_sample.txt');
    final textAndTokens = MsmarcoMiniLmL6V3.tokenizer.tokenize(string);
    final path = await getModelPath('msmarcoMiniLmL6V3.onnx');
    final model = MsmarcoMiniLmL6V3.load(path);
    debugPrint('Loaded model');
    // Warm up. This is not necessary, but it's nice to do. Only the first call
    // to a model is slow.
    for (var i = 0; i < 5; i++) {
      await model.getEmbeddingAsVector(
        textAndTokens[i % textAndTokens.length].tokens,
      );
    }
    debugPrint('Warmed up');

    final stopwatch = Stopwatch()..start();
    var completed = 0;
    while (completed < 20) {
      await model.getEmbeddingAsVector(
          textAndTokens[completed % textAndTokens.length].tokens);
      completed++;
    }
    stopwatch.stop();
    final elapsed = stopwatch.elapsedMilliseconds;
    final speed = (elapsed / completed.toDouble()).round();
    setState(() {
      final numberPerSecond = (1000 / (elapsed / completed)).round();
      _speedTestResult = '$speed ms for 400 words ($numberPerSecond / sec)';
    });
  }
}

Future<String> getModelPath(String modelFilenameWithExtension) async {
  if (kIsWeb) {
    return 'assets/models/msmarcoMiniLmL6V3/$modelFilenameWithExtension';
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
      'assets/models/msmarcoMiniLmL6V3/${path.basename(modelFilenameWithExtension)}';
  final assetByteData = await rootBundle.load(assetPath);
  final assetLength = assetByteData.lengthInBytes;
  final fileSameSize = fileExists && fileLength == assetLength;
  if (!fileExists || !fileSameSize) {
    debugPrint(
        'Copying model to $modelPath. Why? Either the file does not exist (${!fileExists}), '
        'or it does exist but is not the same size as the one in the assets '
        'directory. (${!fileSameSize})');

    List<int> bytes = assetByteData.buffer.asUint8List(
      assetByteData.offsetInBytes,
      assetByteData.lengthInBytes,
    );
    await file.writeAsBytes(bytes, flush: true);
  }

  return modelPath;
}
