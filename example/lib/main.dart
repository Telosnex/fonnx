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
    calloc.free(inputIdsValue);

    final inputMaskValue = calloc<Pointer<OrtValue>>();
    final inputMaskStatus = objects.api.createInt64Tensor(
      inputMaskValue,
      memoryInfo: memoryInfo.value,
      values: List.generate(
        256,
        (index) => index < tokens.length ? 1 : 0,
      ),
    );
    if (inputMaskStatus.isError) {
      final error =
          'Code: ${objects.api.getErrorCodeMessage(inputMaskStatus)}\n'
          'Message: ${objects.api.getErrorMessage(inputMaskStatus)}';
      throw Exception(error);
    }
    calloc.free(inputMaskValue);

    final tokenTypeValue = calloc<Pointer<OrtValue>>();
    final tokenTypeStatus = objects.api.createInt64Tensor(
      tokenTypeValue,
      memoryInfo: memoryInfo.value,
      values: List.generate(
        256,
        (index) => index < tokens.length ? 0 : -1,
      ),
    );
    if (tokenTypeStatus.isError) {
      final error =
          'Code: ${objects.api.getErrorCodeMessage(inputMaskStatus)}\n'
          'Message: ${objects.api.getErrorMessage(inputMaskStatus)}';
      throw Exception(error);
    }
    calloc.free(tokenTypeValue);

    calloc.free(memoryInfo);

    final inputNamesPointer = calloc<Pointer<Pointer<Char>>>(3);
    inputNamesPointer[0] = 'input_ids'.toNativeUtf8().cast();
    inputNamesPointer[1] = 'token_type_ids'.toNativeUtf8().cast();
    inputNamesPointer[2] = 'attention_mask'.toNativeUtf8().cast();
    final inputNames = inputNamesPointer.cast<Pointer<Char>>();
    final inputValues = calloc<Pointer<OrtValue>>(3);
    inputValues[0] = inputIdsValue.value;
    inputValues[1] = tokenTypeValue.value;
    inputValues[2] = inputMaskValue.value;
    final outputNamesPointer = calloc<Pointer<Pointer<Char>>>();
    outputNamesPointer.value = 'last_hidden_state'.toNativeUtf8().cast();
    final outputNames = outputNamesPointer.cast<Pointer<Char>>();
    final outputValues = calloc<Pointer<OrtValue>>();
    final outputCount = 1;

    final runOptionsPtr = calloc<Pointer<OrtRunOptions>>();
    final runOptionsStatus = objects.api.createRunOptions(runOptionsPtr);
    if (runOptionsStatus.isError) {
      final error =
          'Code: ${objects.api.getErrorCodeMessage(runOptionsStatus)}\n'
          'Message: ${objects.api.getErrorMessage(runOptionsStatus)}';
      throw Exception(error);
    }
    final runStatus = objects.api.run(
      session: objects.sessionPtr.value,
      runOptions: runOptionsPtr.value,
      inputNames: inputNames,
      inputValues: inputValues,
      inputCount: 3,
      outputNames: outputNames,
      outputCount: outputCount,
      outputValues: outputValues,
    );
    if (runStatus.isError) {
      final error = 'Code: ${objects.api.getErrorCodeMessage(runStatus)}\n'
          'Message: ${objects.api.getErrorMessage(runStatus)}';
      throw Exception(error);
    }
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
