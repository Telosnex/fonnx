import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:ffi';

import 'package:fonnx/fonnx.dart' hide calloc;
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
                  DynamicLibrary.open('libonnxruntime.1.16.0.dylib');
                  final baseApi = OrtGetApiBase().ref;
                  final api = baseApi.GetApi.asFunction<
                      Pointer<OrtApi> Function(int)>();
                  final ortApi = api(ORT_API_VERSION).ref;
                  final envPtr = calloc<Pointer<OrtEnv>>();
                  final status = ortApi.createEnv(envPtr);
                  if (status.isError) {
                    final error =
                        'Code: ${ortApi.getErrorCodeMessage(status)}\n'
                        'Message: ${ortApi.getErrorMessage(status)}';
                    throw Exception(error);
                  }
                  final sessionOptionsPtr =
                      calloc<Pointer<OrtSessionOptions>>();
                  final sessionOptions =
                      ortApi.createSessionOptions(sessionOptionsPtr);
                  if (status.isError) {
                    final error =
                        'Code: ${ortApi.getErrorCodeMessage(status)}\n'
                        'Message: ${ortApi.getErrorMessage(status)}';
                    throw Exception(error);
                  }
                  final sessionPtr = calloc<Pointer<OrtSession>>();
                  final modelPath = '/Users/alexander/Downloads/model.onnx';
                  final sessionStatus = ortApi.createSession(
                    env: envPtr.value,
                    modelPath: modelPath,
                    sessionOptions: sessionOptionsPtr.value,
                    session: sessionPtr,
                  );
                  if (sessionStatus.isError) {
                    final error =
                        'Code: ${ortApi.getErrorCodeMessage(sessionStatus)}\n'
                        'Message: ${ortApi.getErrorMessage(sessionStatus)}';
                    throw Exception(error);
                  }
                  print('did it');
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
}

extension DartNativeFunctions on OrtApi {
  String? getErrorCodeMessage(Pointer<OrtStatus> status) {
    final getErrorCodeFn =
        GetErrorCode.asFunction<int Function(Pointer<OrtStatus>)>();
    final errorCodeResult = getErrorCodeFn(status);

    return messageForOrtErrorCode(errorCodeResult);
  }

  String getErrorMessage(Pointer<OrtStatus> status) {
    final getErrorMessageFn = GetErrorMessage.asFunction<
        Pointer<Char> Function(Pointer<OrtStatus>)>();
    final message = getErrorMessageFn(status);
    return message.toDartString();
  }

  Pointer<OrtStatus> createEnv(
    Pointer<Pointer<OrtEnv>> env, {
    int logLevel = OrtLoggingLevel.ORT_LOGGING_LEVEL_ERROR,
    String logId = '',
  }) {
    final createEnvFn = CreateEnv.asFunction<
        Pointer<OrtStatus> Function(
            int, Pointer<Char>, Pointer<Pointer<OrtEnv>>)>();
    final status = createEnvFn(
      logLevel,
      logId.toNativeUtf8().cast<Char>(),
      Pointer.fromAddress(env.address),
    );
    return status;
  }

  Pointer<OrtStatus> createSession(
      {required Pointer<OrtEnv> env,
      required String modelPath,
      required Pointer<OrtSessionOptions> sessionOptions,
      required Pointer<Pointer<OrtSession>> session}) {
    final createSessionFn = CreateSession.asFunction<
        Pointer<OrtStatus> Function(Pointer<OrtEnv>, Pointer<Char>,
            Pointer<OrtSessionOptions>, Pointer<Pointer<OrtSession>>)>();
    final status = createSessionFn(
      env,
      modelPath.toNativeUtf8().cast<Char>(),
      sessionOptions,
      session,
    );
    return status;
  }

  Pointer<OrtStatus> createSessionOptions(
    Pointer<Pointer<OrtSessionOptions>> optionsPtr,
  ) {
    final createSessionOptionsFn = CreateSessionOptions.asFunction<
        Pointer<OrtStatus> Function(Pointer<Pointer<OrtSessionOptions>>)>();
    final status = createSessionOptionsFn(optionsPtr);
    return status;
  }
}

extension on Pointer<OrtStatus> {
  bool get isError {
    return address != 0;
  }
}

extension PointerCharExtension on Pointer<Char> {
  String toDartString() {
    return cast<Utf8>().toDartString();
  }
}

String? messageForOrtErrorCode(int code) {
  if (code == 0) {
    return null;
  } else if (code == 1) {
    return 'Failed';
  } else if (code == 2) {
    return 'Invalid argument';
  } else if (code == 3) {
    return 'No such file';
  } else if (code == 4) {
    return 'No model';
  } else if (code == 5) {
    return 'Engine error';
  } else if (code == 6) {
    return 'Runtime exception';
  } else if (code == 7) {
    return 'Invalid protobuf';
  } else if (code == 8) {
    return 'Model loaded';
  } else if (code == 9) {
    return 'Not implemented';
  } else if (code == 10) {
    return 'Invalid graph';
  } else if (code == 11) {
    return 'EP fail';
  } else {
    return 'Unknown OrtErrorCode: $code';
  }
}
