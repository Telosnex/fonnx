import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:fonnx/onnx/ort_ffi_bindings.dart' hide calloc, free;
import 'package:ffi/ffi.dart';

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

  Pointer<OrtStatus> createInt64Tensor(
    Pointer<Pointer<OrtValue>> inputTensorPointer, {
    required Pointer<OrtMemoryInfo> memoryInfo,
    required List<int> values,
  }) {
    final sizeOfInt64 = sizeOf<Int64>();
    final inputTensorNative = calloc<Int64>(values.length * sizeOfInt64);

    for (var i = 0; i < values.length; i++) {
      inputTensorNative[i] = values[i];
    }

    final inputShape = calloc<Int64>(2 * sizeOfInt64);
    inputShape[0] = 1;
    inputShape[1] = values.length;

    final ptrVoid = inputTensorNative.cast<Void>();
    final status = createTensorWithDataAsOrtValue(
      inputTensorPointer,
      memoryInfo: memoryInfo,
      inputData: ptrVoid,
      inputDataLengthInBytes: values.length * sizeOfInt64,
      inputShape: inputShape,
      inputShapeLengthInBytes: 2,
      onnxTensorElementDataType:
          ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64,
    );
    // calloc.free(inputTensorNative);
    if (status.isError) {
      final error = 'Code: ${getErrorCodeMessage(status)}\n'
          'Message: ${getErrorMessage(status)}';
      throw Exception(error);
    }
    return status;
  }

  Pointer<OrtStatus> sessionGetOutputCount(Pointer<OrtSession> session) {
    final getOutputCountFn = SessionGetOutputCount.asFunction<
        Pointer<OrtStatus> Function(
          Pointer<OrtSession>,
          Pointer<Size>,
        )>();
    final outputCount = calloc<Size>();
    final status = getOutputCountFn(session, outputCount);
    return status;
  }

  Pointer<OrtStatus> sessionGetOutputName(
    Pointer<OrtSession> session,
    int index,
    Pointer<Pointer<Char>> out,
  ) {
    final getFn = SessionGetOutputName.asFunction<
        Pointer<OrtStatus> Function(
          Pointer<OrtSession>,
          int,
          Pointer<OrtAllocator>,
          Pointer<Pointer<Char>>,
        )>();
    final allocator = calloc<Pointer<OrtAllocator>>();
    getAllocatorWithDefaultOptions(allocator);
    final status = getFn(session, index, allocator.value, out);
    return status;
  }

  Pointer<OrtStatus> createRunOptions(
    Pointer<Pointer<OrtRunOptions>> runOptions,
  ) {
    final createRunOptionsFn = CreateRunOptions.asFunction<
        Pointer<OrtStatus> Function(Pointer<Pointer<OrtRunOptions>>)>();
    final status = createRunOptionsFn(runOptions);
    if (status.isError) {
      final error = 'Code: ${getErrorCodeMessage(status)}\n'
          'Message: ${getErrorMessage(status)}';
      throw Exception(error);
    }
    return status;
  }

  Pointer<OrtStatus> createTensorWithDataAsOrtValue(
    Pointer<Pointer<OrtValue>> value, {
    required Pointer<OrtMemoryInfo> memoryInfo,
    required Pointer<Void> inputData,
    required int inputDataLengthInBytes,
    required Pointer<Int64> inputShape,
    required int inputShapeLengthInBytes,
    required int onnxTensorElementDataType,
  }) {
    final createTensorWithDataFn = CreateTensorWithDataAsOrtValue.asFunction<
        Pointer<OrtStatus> Function(Pointer<OrtMemoryInfo>, Pointer<Void>, int,
            Pointer<Int64>, int, int, Pointer<Pointer<OrtValue>> out)>();
    final status = createTensorWithDataFn(
      memoryInfo,
      inputData,
      inputDataLengthInBytes,
      inputShape,
      inputShapeLengthInBytes,
      onnxTensorElementDataType,
      value,
    );
    return status;
  }

  Pointer<OrtStatus> createCpuMemoryInfo(
    Pointer<Pointer<OrtMemoryInfo>> memoryInfo, {
    int ortAllocator = OrtAllocatorType.OrtArenaAllocator,
    int ortMemType = OrtMemType.OrtMemTypeDefault,
  }) {
    final createCpuMemoryInfoFn = CreateCpuMemoryInfo.asFunction<
        Pointer<OrtStatus> Function(
            int, int, Pointer<Pointer<OrtMemoryInfo>>)>();
    final status = createCpuMemoryInfoFn(
      ortAllocator,
      ortMemType,
      memoryInfo,
    );
    if (status.isError) {
      final error = 'Code: ${getErrorCodeMessage(status)}\n'
          'Message: ${getErrorMessage(status)}';
      throw Exception(error);
    }
    return status;
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
    final modelPathChars = defaultTargetPlatform == TargetPlatform.windows ? modelPath.toNativeUtf16().cast<Char>() : modelPath.toNativeUtf8().cast<Char>();
    final status = createSessionFn(
      env,
      modelPathChars,
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
    if (status.isError) {
      final error = 'Code: ${getErrorCodeMessage(status)}\n'
          'Message: ${getErrorMessage(status)}';
      throw Exception(error);
    }
    return status;
  }

  Pointer<OrtStatus> getAllocatorWithDefaultOptions(
      Pointer<Pointer<OrtAllocator>> out) {
    final getAllocatorWithDefaultOptionsFn =
        GetAllocatorWithDefaultOptions.asFunction<
            Pointer<OrtStatus> Function(Pointer<Pointer<OrtAllocator>>)>();
    final status = getAllocatorWithDefaultOptionsFn(out);
    return status;
  }

  Pointer<OrtStatus> getTensorMutableData(
    Pointer<OrtValue> value,
    Pointer<Pointer<Void>> out,
  ) {
    final getTensorMutableDataFn = GetTensorMutableData.asFunction<
        Pointer<OrtStatus> Function(
            Pointer<OrtValue>, Pointer<Pointer<Void>>)>();
    final status = getTensorMutableDataFn(value, out);
    if (status.isError) {
      final error =
          'Get tensor data failed. Code: ${getErrorCodeMessage(status)}\n'
          'Message: ${getErrorMessage(status)}';
      throw Exception(error);
    }
    return status;
  }

  Pointer<OrtStatus> getTensorTypeAndShape(
    Pointer<OrtValue> value,
    Pointer<Pointer<OrtTensorTypeAndShapeInfo>> out,
  ) {
    final getTensorTypeAndShapeFn = GetTensorTypeAndShape.asFunction<
        Pointer<OrtStatus> Function(
            Pointer<OrtValue>, Pointer<Pointer<OrtTensorTypeAndShapeInfo>>)>();
    final status = getTensorTypeAndShapeFn(value, out);
    if (status.isError) {
      final error =
          'Get tensor type and shape failed. Code: ${getErrorCodeMessage(status)}\n'
          'Message: ${getErrorMessage(status)}';
      throw Exception(error);
    }
    return status;
  }

  Pointer<OrtStatus> getTensorShapeElementCount(
    Pointer<OrtTensorTypeAndShapeInfo> info,
    Pointer<Size> out,
  ) {
    final getTensorShapeElementCountFn = GetTensorShapeElementCount.asFunction<
        Pointer<OrtStatus> Function(
            Pointer<OrtTensorTypeAndShapeInfo>, Pointer<Size>)>();
    final status = getTensorShapeElementCountFn(info, out);
    if (status.isError) {
      final error =
          'Get tensor shape element count failed. Code: ${getErrorCodeMessage(status)}\n'
          'Message: ${getErrorMessage(status)}';
      throw Exception(error);
    }
    return status;
  }

  Pointer<OrtStatus> run({
    required Pointer<OrtSession> session,
    required Pointer<OrtRunOptions> runOptions,
    required Pointer<Pointer<Char>> inputNames,
    required Pointer<Pointer<OrtValue>> inputValues,
    required int inputCount,
    required Pointer<Pointer<Char>> outputNames,
    required int outputCount,
    required Pointer<Pointer<OrtValue>> outputValues,
  }) {
    final runFn = Run.asFunction<
        Pointer<OrtStatus> Function(
          Pointer<OrtSession>,
          Pointer<OrtRunOptions>,
          Pointer<Pointer<Char>>,
          Pointer<Pointer<OrtValue>>,
          int,
          Pointer<Pointer<Char>>,
          int,
          Pointer<Pointer<OrtValue>>,
        )>();
    final status = runFn(
      session,
      runOptions,
      inputNames,
      inputValues,
      inputCount,
      outputNames,
      outputCount,
      outputValues,
    );
    if (status.isError) {
      final error = 'Run failed. Code: ${getErrorCodeMessage(status)}\n'
          'Message: ${getErrorMessage(status)}';
      throw Exception(error);
    }
    return status;
  }

  Pointer<OrtStatus> sessionOptionsAppendExecutionProviderCoreML(
    Pointer<OrtSessionOptions> options,
    int coremlFlags,
  ) {
    final status = OrtSessionOptionsAppendExecutionProvider_CoreML(
      options,
      coremlFlags,
    );

    if (status.isError) {
      final error =
          'SessionOptionsAppendExecutionProvider_CoreML failed. Code: ${getErrorCodeMessage(status)}\n'
          'Message: ${getErrorMessage(status)}';
      throw Exception(error);
    }
    return status;
  }

  Pointer<OrtStatus> setIntraOpNumThreads(
    Pointer<OrtSessionOptions> options,
    int intraOpNumThreads,
  ) {
    final fn = SetIntraOpNumThreads.asFunction<
        Pointer<OrtStatus> Function(Pointer<OrtSessionOptions>, int)>();
    final status = fn(options, intraOpNumThreads);
    if (status.isError) {
      final error =
          'SessionOptionsSetIntraOpNumThreads failed. Code: ${getErrorCodeMessage(status)}\n'
          'Message: ${getErrorMessage(status)}';
      throw Exception(error);
    }
    return status;
  }

  Pointer<OrtStatus> setInterOpNumThreads(
    Pointer<OrtSessionOptions> options,
    int interOpNumThreads,
  ) {
    final fn = SetInterOpNumThreads.asFunction<
        Pointer<OrtStatus> Function(Pointer<OrtSessionOptions>, int)>();
    final status = fn(options, interOpNumThreads);
    if (status.isError) {
      final error =
          'SessionOptionsSetInterOpNumThreads failed. Code: ${getErrorCodeMessage(status)}\n'
          'Message: ${getErrorMessage(status)}';
      throw Exception(error);
    }
    return status;
  }
}

class OrtSessionObjects {
  final Pointer<Pointer<OrtSession>> sessionPtr;
  final OrtApiBase apiBase;
  final OrtApi api;

  OrtSessionObjects({
    required this.sessionPtr,
    required this.apiBase,
    required this.api,
  });
}

String get dylibPath {
  final isTesting = !kIsWeb && Platform.environment['FLUTTER_TEST'] == 'true';
  if (isTesting) {
    return 'macos/onnx_runtime/osx/libonnxruntime.1.16.0.dylib';
  }
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      throw 'Android runs using a platform-specific implementation, not FFI';
    case TargetPlatform.fuchsia:
      throw UnimplementedError();
    case TargetPlatform.iOS:
      throw 'iOS runs using a platform-specific implementation, not FFI';
    case TargetPlatform.linux:
      return 'libonnxruntime.so.1.16.0';
    case TargetPlatform.macOS:
      return 'libonnxruntime.1.16.0.dylib';
    case TargetPlatform.windows:
      return 'onnxruntime-x64.dll';
  }
}
/// You MUST call [calloc.free] on the returned pointer when you are done with it.
///
/// It is reasonable to never free it in an app where you would like the model
/// to be loaded for the lifetime of the app.
OrtSessionObjects createOrtSession(String modelPath) {
  // Used to have:
  //   DynamicLibrary.open(dylibPath);
  //   final baseApi = OrtGetApiBase().ref;
  // That led to an error that said:
  //   
  // After reading [this Github issue](https://github.com/dart-lang/sdk/issues/50551)
  //   my instinct was there may be an issue with global static functions and ffi,
  //   and Linux may be lagging in support. Explicitly looking the function up in
  //   the explicit library did fix it.
  final lib = DynamicLibrary.open(dylibPath);
  final fn = lib.lookupFunction<Pointer<OrtApiBase> Function(), Pointer<OrtApiBase> Function()>('OrtGetApiBase');
  final answer = fn.call();
  final baseApi = answer.ref;
  final api = baseApi.GetApi.asFunction<Pointer<OrtApi> Function(int)>();
  final ortApi = api(ORT_API_VERSION).ref;
  final envPtr = calloc<Pointer<OrtEnv>>();
  final status = ortApi.createEnv(envPtr);
  if (status.isError) {
    final error = 'Code: ${ortApi.getErrorCodeMessage(status)}\n'
        'Message: ${ortApi.getErrorMessage(status)}';
    throw Exception(error);
  }

  final sessionOptionsPtr = calloc<Pointer<OrtSessionOptions>>();
  final sessionPtr = calloc<Pointer<OrtSession>>();
  ortApi.createSessionOptions(sessionOptionsPtr);
  // Avoiding setting inter/intra op num threads at all seems to get the best performance.
  // 128 threads: ~5.00 ms/embedding
  // 1 thread: ~0.85 ms/embedding
  // 7 threads: ~0.65 ms/embedding
  // Not setting inter/intra op num threads: ~0.65 ms/embedding

  // Adding CoreML support slowed down inference about 10x on M2 Max.
  // This persisted even when CPU only + only if ANE is available flags were
  // set, either together or independently.
  final sessionStatus = ortApi.createSession(
    env: envPtr.value,
    modelPath: modelPath,
    sessionOptions: sessionOptionsPtr.value,
    session: sessionPtr,
  );
  if (sessionStatus.isError) {
    final error = 'Code: ${ortApi.getErrorCodeMessage(sessionStatus)}\n'
        'Message: ${ortApi.getErrorMessage(sessionStatus)}';
    throw Exception(error);
  }



  // calloc.free(sessionOptionsPtr);
  // calloc.free(envPtr);
  return OrtSessionObjects(
    sessionPtr: sessionPtr,
    apiBase: baseApi,
    api: ortApi,
  );
}

extension IsError on Pointer<OrtStatus> {
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
