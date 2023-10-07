import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';

import 'package:flutter/services.dart';
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
                  ffi.DynamicLibrary.open('libonnxruntime.1.16.0.dylib');
                  final api = OrtGetApiBase().ref;
                  final versionFn = api.GetVersionString.asFunction<
                      ffi.Pointer<ffi.Char> Function()>();
                  final version = versionFn().toDartString();
                  setState(() {
                    _onnxVersion = version;
                  });
                },
                icon: const Icon(Icons.code),
                label: const Text('Load dylib'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension PointerCharExtension on ffi.Pointer<ffi.Char> {
  String toDartString() {
    return cast<Utf8>().toDartString();
  }
}
