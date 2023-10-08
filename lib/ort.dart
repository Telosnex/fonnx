import 'dart:ffi';

import 'package:fonnx/fonnx.dart' hide calloc, free;
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
    calloc.free(inputTensorNative);
    return status;
  }

  Pointer<OrtStatus> createRunOptions(
    Pointer<Pointer<OrtRunOptions>> runOptions,
  ) {
    final createRunOptionsFn = CreateRunOptions.asFunction<
        Pointer<OrtStatus> Function(Pointer<Pointer<OrtRunOptions>>)>();
    final status = createRunOptionsFn(runOptions);
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
    return runFn(
      session,
      runOptions,
      inputNames,
      inputValues,
      inputCount,
      outputNames,
      outputCount,
      outputValues,
    );
  }
}

class OrtObjects {
  final Pointer<Pointer<OrtSession>> sessionPtr;
  final OrtApiBase apiBase;
  final OrtApi api;

  OrtObjects({
    required this.sessionPtr,
    required this.apiBase,
    required this.api,
  });
}

/// You MUST call [calloc.free] on the returned pointer when you are done with it.
///
/// It is reasonable to never free it in an app where you would like the model
/// to be loaded for the lifetime of the app.
OrtObjects createOrtSession(String modelPath) {
  DynamicLibrary.open('libonnxruntime.1.16.0.dylib');
  final baseApi = OrtGetApiBase().ref;
  final api = baseApi.GetApi.asFunction<Pointer<OrtApi> Function(int)>();
  final ortApi = api(ORT_API_VERSION).ref;
  final envPtr = calloc<Pointer<OrtEnv>>();
  final status = ortApi.createEnv(envPtr);
  if (status.isError) {
    final error = 'Code: ${ortApi.getErrorCodeMessage(status)}\n'
        'Message: ${ortApi.getErrorMessage(status)}';
    throw Exception(error);
  }

  // Load the model.
  // == CALLOC ==
  final sessionOptionsPtr = calloc<Pointer<OrtSessionOptions>>();
  final sessionPtr = calloc<Pointer<OrtSession>>();

  final sessionOptions = ortApi.createSessionOptions(sessionOptionsPtr);
  if (status.isError) {
    final error = 'Code: ${ortApi.getErrorCodeMessage(status)}\n'
        'Message: ${ortApi.getErrorMessage(status)}';
    throw Exception(error);
  }

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
  calloc.free(sessionOptionsPtr);
  calloc.free(envPtr);
  return OrtObjects(
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
