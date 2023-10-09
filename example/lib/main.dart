import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:path/path.dart' as path;

import 'package:fonnx/fonnx.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _platformVersion = 'Unknown';
  String _lastStatusText = '';
  final _fonnxPlugin = Fonnx();

  @override
  void initState() {
    super.initState();
    initPlatformState();
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> initPlatformState() async {
    String platformVersion;
    // Platform messages may fail, so we use a try/catch PlatformException.
    // We also handle the message potentially returning null.
    try {
      platformVersion =
          await _fonnxPlugin.getPlatformVersion() ?? 'Unknown platform version';
    } on PlatformException {
      platformVersion = 'Failed to get platform version.';
    }

    // If the widget was removed from the tree while the asynchronous platform
    // message was in flight, we want to discard the reply rather than calling
    // setState to update our non-existent appearance.
    if (!mounted) return;

    setState(() {
      _platformVersion = platformVersion;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: Center(
          child: Column(
            children: [
              Text('Running on: $_platformVersion\n'),
              ElevatedButton.icon(
                onPressed: () async {
                  final modelPath = await getModelPath('miniLmL6V2.onnx');
                  final miniLmL6V2 = MiniLmL6V2(modelPath);
                  final embedding = await miniLmL6V2.getEmbedding('');
                  setState(() {
                    _lastStatusText =
                        'MiniLM-L6-V2: Success! ${embedding.length} elements.';
                  });
                },
                icon: const Icon(Icons.code),
                label: const Text('Test MiniLM-L6-V2'),
              ),
              if (_lastStatusText.isNotEmpty) Text(_lastStatusText),
            ],
          ),
        ),
      ),
    );
  }
}

Future<String> getModelPath(String modelFilenameWithExtension) async {
  final assetCacheDirectory =
      await path_provider.getApplicationSupportDirectory();
  final modelPath =
      path.join(assetCacheDirectory.path, modelFilenameWithExtension);

  File file = File(modelPath);
  bool fileExists = await file.exists();
  bool fileSameSize = fileExists &&
      (await file.length()) ==
          (await rootBundle.load(
            path.join(
              "..", // '..' only needed because this example is in a sibling directory of fonnx
              "models",
              "miniLmL6V2",
              path.basename(modelFilenameWithExtension),
            ),
          ))
              .lengthInBytes;
  if (!fileExists || !fileSameSize) {
    debugPrint(
        'Copying model to $modelPath. Why? Either the file does not exist (${!fileExists}), '
        'or it does exist but is not the same size as the one in the assets '
        'directory. (${!fileSameSize})');
    ByteData data = await rootBundle.load(
      path.join(
        "..", // '..' only needed because this example is in a sibling directory of fonnx
        "models",
        "miniLmL6V2",
        path.basename(modelFilenameWithExtension),
      ),
    );
    List<int> bytes =
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    await file.writeAsBytes(bytes);
  }

  return modelPath;
}

/// Helps identify the asset path to pass to RootBundle.load().
void debugAssetPathLocation() async {
  final manifestContent = await rootBundle.loadString('AssetManifest.json');
  final Map<String, dynamic> manifestMap = json.decode(manifestContent);
  debugPrint(manifestMap.toString());
}
