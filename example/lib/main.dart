import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fonnx/tokenizers/wordpiece_tokenizer.dart';
import 'dart:async';
import 'dart:ffi';
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:path/path.dart' as path;

import 'package:fonnx/fonnx.dart' hide calloc, free;
import 'package:ffi/ffi.dart';

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
  String _onnxVersion = 'Unknown';
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
              Text('Running on ONNX: $_onnxVersion\n'),
              ElevatedButton.icon(
                onPressed: () {
                  DynamicLibrary.open('libonnxruntime.1.16.0.dylib');
                  final baseApi = OrtGetApiBase().ref;
                  final versionFn = baseApi.GetVersionString.asFunction<
                      Pointer<Char> Function()>();
                  final version = versionFn().toDartString();
                  setState(() {
                    _onnxVersion = version;
                  });
                  final api = baseApi.GetApi.asFunction<
                      Pointer<OrtApi> Function(int)>();
                  final ortApi = api(ORT_API_VERSION).ref;
                },
                icon: const Icon(Icons.code),
                label: const Text('Load ONNX Runtime'),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  _loadModel();
                },
                icon: const Icon(Icons.code),
                label: const Text('Load ONNX Environment'),
              ),
            ],
          ),
        ),
      ),
    );
  }
  // Pointer<OrtStatus> createTensorWithDataAsOrtValue(
  //   Pointer<Pointer<OrtValue>> value, {
  //   required Pointer<OrtMemoryInfo> memoryInfo,
  //   required Pointer<Void> inputData,
  //   required int inputDataLengthInBytes,
  //   required Pointer<Int64> inputShape,
  //   required int inputShapeLengthInBytes,
  //   required int onnxTensorElementDataType,
  // }) {
  void _loadModel() async {
    final modelPath = await getModelPath('miniLmL6V2.onnx');
    final objects = createOrtSession(modelPath);
    final memoryInfo = calloc<Pointer<OrtMemoryInfo>>();
    final status = objects.api.createCpuMemoryInfo(memoryInfo);
    if (status.isError) {
      final error = 'Code: ${objects.api.getErrorCodeMessage(status)}\n'
          'Message: ${objects.api.getErrorMessage(status)}';
      throw Exception(error);
    }
    final inputIdsValue = calloc<Pointer<OrtValue>>();
    final tokens = WordpieceTokenizer.bert().tokenize('');
    final inputIdsStatus = objects.api.createInt64Tensor(
      inputIdsValue,
      memoryInfo: memoryInfo.value,
      values: tokens,

    );
    if (inputIdsStatus.isError) {
      final error = 'Code: ${objects.api.getErrorCodeMessage(inputIdsStatus)}\n'
          'Message: ${objects.api.getErrorMessage(inputIdsStatus)}';
      throw Exception(error);
    }
    final inputMask = List.generate(256, (index) {
      if (index < tokens.length) {
        return 1;
      } else {
        return 0;
      }
    });
    final inputMaskValue = calloc<Pointer<OrtValue>>();
    final inputMaskStatus = objects.api.createInt64Tensor(
      inputMaskValue,
      memoryInfo: memoryInfo.value,
      values: inputMask,
    );

    print('did it');
  }
}

Future<String> getModelPath(String modelFilenameWithExtension) async {
  final assetCacheDirectory =
      await path_provider.getApplicationSupportDirectory();
  final modelPath =
      path.join(assetCacheDirectory.path, modelFilenameWithExtension);

  File file = File(modelPath);
  bool fileExists = await file.exists();
  if (!fileExists) {
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
