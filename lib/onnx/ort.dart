import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:fonnx/dylib_path_overrides.dart';
import 'package:fonnx/onnx/ort_extensions.dart';
import 'package:fonnx/onnx/ort_ffi_bindings.dart' hide calloc, free, malloc;
import 'package:ffi/ffi.dart';

final class _OrtSessionFinalizerContext extends Struct {
  external Pointer<Pointer<OrtSession>> session;
  external Pointer<Pointer<OrtEnv>> env;
  external Pointer<NativeFunction<Void Function(Pointer<OrtSession>)>>
  releaseSession;
  external Pointer<NativeFunction<Void Function(Pointer<OrtEnv>)>> releaseEnv;
}

@Native<Void Function(Pointer<Void>)>(
  symbol: 'fonnx_release_ort_session_context',
  assetId: 'package:fonnx/onnx/ort_session_finalizer.dart',
)
external void _releaseOrtSessionContext(Pointer<Void> context);

@Native<Uint32 Function()>(
  symbol: 'fonnx_ort_session_finalizer_abi_version',
  assetId: 'package:fonnx/onnx/ort_session_finalizer.dart',
)
external int fonnxOrtSessionFinalizerAbiVersion();

@Native<Pointer<Utf8> Function()>(
  symbol: 'fonnx_ort_session_finalizer_build_info',
  assetId: 'package:fonnx/onnx/ort_session_finalizer.dart',
)
external Pointer<Utf8> _fonnxOrtSessionFinalizerBuildInfo();

String get fonnxOrtSessionFinalizerBuildInfo =>
    _fonnxOrtSessionFinalizerBuildInfo().toDartString();

final _ortSessionFinalizer = NativeFinalizer(
  Native.addressOf<NativeFinalizerFunction>(_releaseOrtSessionContext),
);

extension DartNativeFunctions on OrtApi {
  String? getErrorCodeMessage(Pointer<OrtStatus> status) {
    final getErrorCodeFn =
        GetErrorCode.asFunction<int Function(Pointer<OrtStatus>)>();
    final errorCodeResult = getErrorCodeFn(status);

    return messageForOrtErrorCode(errorCodeResult);
  }

  /// Copies the error message and releases the owned ORT status.
  ///
  /// Call [getErrorCodeMessage] first if both values are needed. ORT requires
  /// every non-null status to be released exactly once.
  String consumeErrorMessage(Pointer<OrtStatus> status) {
    final getErrorMessageFn =
        GetErrorMessage.asFunction<
          Pointer<Char> Function(Pointer<OrtStatus>)
        >();
    final message = getErrorMessageFn(status);
    final result = message.toDartString();
    ReleaseStatus.asFunction<void Function(Pointer<OrtStatus>)>()(status);
    return result;
  }

  Pointer<Float> createFloat32Tensor(
    Pointer<Pointer<OrtValue>> inputTensorPointer, {
    required Pointer<OrtMemoryInfo> memoryInfo,
    required List<double> values,
  }) {
    final sizeOfFloat32 = sizeOf<Float>();
    final inputTensorNative = calloc<Float>(values.length * sizeOfFloat32);
    final float32List = Float32List.fromList(values);
    for (var i = 0; i < values.length; i++) {
      inputTensorNative[i] = float32List[i];
    }
    final inputShape = calloc<Int64>(sizeOf<Int64>());
    inputShape[0] = values.length;
    final ptrVoid = inputTensorNative.cast<Void>();
    final status = createTensorWithDataAsOrtValue(
      inputTensorPointer,
      memoryInfo: memoryInfo,
      inputData: ptrVoid,
      inputDataLengthInBytes: values.length * sizeOfFloat32,
      inputShape: inputShape,
      inputShapeLengthInBytes: 1,
      onnxTensorElementDataType:
          ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT.value,
    );
    if (status.isError) {
      final error =
          'Code: ${getErrorCodeMessage(status)}\n'
          'Message: ${consumeErrorMessage(status)}';
      calloc.free(inputTensorNative);
      calloc.free(inputShape);
      throw Exception(error);
    }
    calloc.free(inputShape);
    return inputTensorNative;
  }

  Pointer<Float> createFloat32Tensor2DFromInts(
    Pointer<Pointer<OrtValue>> inputTensorPointer, {
    required Pointer<OrtMemoryInfo> memoryInfo,
    required List<List<int>> values,
  }) {
    final flatArray = values.expand((i) => i).toList();
    final inputTensorNative = calloc<Float>(flatArray.length);
    for (var i = 0; i < flatArray.length; i += 1) {
      inputTensorNative[i] = flatArray[i].toDouble();
      // Extremely useful for debugging failures, allows comparison of Magika
      // example code's input array to our input array.
      //
      // Magika can be thought of as a model that takes 1536 bytes and returns
      // a 113-length vector of floats.
      //
      // The bytes have to become floats, have leading and trailing whitespace
      // trimmed. These requirements are non-obvious and only were identified
      // through failing tests. Moreover, tests are very sensitive due to the
      // nature of the model and the size of the test files. ex. trimming one
      // whitespace character in html.htm led to it being detected as
      // javascript.
      // print(
      //     'inputTensorNative[$i] => ${flatArray[i]} => ${inputTensorNative[i]}');
    }
    final inputShape = calloc<Int64>(2);
    inputShape[0] = 1;
    inputShape[1] = flatArray.length;
    final ptrVoid = inputTensorNative.cast<Void>();
    final status = createTensorWithDataAsOrtValue(
      inputTensorPointer,
      memoryInfo: memoryInfo,
      inputData: ptrVoid,
      inputDataLengthInBytes: flatArray.length * sizeOf<Float>(),
      inputShape: inputShape,
      inputShapeLengthInBytes: 2,
      onnxTensorElementDataType:
          ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT.value,
    );
    if (status.isError) {
      final error =
          'Code: ${getErrorCodeMessage(status)}\n'
          'Message: ${consumeErrorMessage(status)}';
      calloc.free(inputTensorNative);
      calloc.free(inputShape);
      throw Exception(error);
    }
    calloc.free(inputShape);
    return inputTensorNative;
  }

  Pointer<Float> createFloat32Tensor2D(
    Pointer<Pointer<OrtValue>> inputTensorPointer, {
    required Pointer<OrtMemoryInfo> memoryInfo,
    required List<List<double>> values,
  }) {
    // Determine the size of a float in bytes
    final sizeOfFloat32 = sizeOf<Float>();

    // Flatten the 2D array and get total number of elements
    final allValues = values.expand((i) => i).toList();
    final totalElements = allValues.length;

    // Allocate native memory for the flattened array
    final inputTensorNative = calloc<Float>(totalElements);
    final float32List = Float32List.fromList(allValues);
    for (var i = 0; i < totalElements; i++) {
      inputTensorNative[i] = float32List[i];
    }

    // Allocate memory for the shape (2 dimensions)
    final inputShape = calloc<Int64>(2);
    inputShape[0] = values.length; // Number of rows
    inputShape[1] = values.first.length; // Number of columns

    final ptrVoid = inputTensorNative.cast<Void>();
    final status = createTensorWithDataAsOrtValue(
      inputTensorPointer,
      memoryInfo: memoryInfo,
      inputData: ptrVoid,
      inputDataLengthInBytes: totalElements * sizeOfFloat32,
      inputShape: inputShape,
      inputShapeLengthInBytes: 2, // We now have two dimensions
      onnxTensorElementDataType:
          ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT.value,
    );

    if (status.isError) {
      final error =
          'Code: ${getErrorCodeMessage(status)}\n'
          'Message: ${consumeErrorMessage(status)}';
      calloc.free(inputTensorNative);
      calloc.free(inputShape);
      throw Exception(error);
    }

    calloc.free(inputShape);
    return inputTensorNative;
  }

  Pointer<Float> createFloat32Tensor3D(
    Pointer<Pointer<OrtValue>> inputTensorPointer, {
    required Pointer<OrtMemoryInfo> memoryInfo,
    required List<List<List<double>>> values,
  }) {
    // Determine the size of a float in bytes
    final sizeOfFloat32 = sizeOf<Float>();

    // Flatten the 3D array to a 1D array and get total number of elements
    final allValues = values.expand((i) => i.expand((j) => j)).toList();
    final totalElements = allValues.length;

    // Allocate native memory for the flattened array
    final inputTensorNative = calloc<Float>(totalElements);
    final float32List = Float32List.fromList(allValues);
    for (var i = 0; i < totalElements; i++) {
      inputTensorNative[i] = float32List[i];
    }

    // Allocate memory for the shape (3 dimensions)
    final inputShape = calloc<Int64>(3);
    inputShape[0] = values.length; // Depth: Number of 2D arrays
    inputShape[1] =
        values.first.length; // Rows: Number of rows in the first 2D array
    inputShape[2] = values
        .first
        .first
        .length; // Columns: Number of columns in the first row

    final ptrVoid = inputTensorNative.cast<Void>();
    final status = createTensorWithDataAsOrtValue(
      inputTensorPointer,
      memoryInfo: memoryInfo,
      inputData: ptrVoid,
      inputDataLengthInBytes: totalElements * sizeOfFloat32,
      inputShape: inputShape,
      inputShapeLengthInBytes: 3, // We now have three dimensions
      onnxTensorElementDataType:
          ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT.value,
    );

    if (status.isError) {
      final error =
          'Code: ${getErrorCodeMessage(status)}\n'
          'Message: ${consumeErrorMessage(status)}';
      calloc.free(inputTensorNative);
      calloc.free(inputShape);
      throw Exception(error);
    }

    calloc.free(inputShape);
    return inputTensorNative;
  }

  /// You MUST call [calloc.free] on the returned pointer when you are done with
  /// it, i.e. once inference is complete.
  Pointer<Int64> createInt64Tensor(
    Pointer<Pointer<OrtValue>> inputTensorPointer, {
    required Pointer<OrtMemoryInfo> memoryInfo,
    required List<int> values,
    List<int>? shape,
  }) {
    // Compatibility with what method assumed prior to shape being in API.
    shape = shape ?? [1, values.length];
    final sizeOfInt64 = sizeOf<Int64>();
    final inputTensorNative = calloc<Int64>(values.length * sizeOfInt64);

    for (var i = 0; i < values.length; i++) {
      inputTensorNative[i] = values[i];
    }

    // If shape is provided, use it; otherwise default to 1D tensor with shape [values.length]
    final inputShapeLengthInBytes = shape.length;
    final inputShape = calloc<Int64>(inputShapeLengthInBytes * sizeOfInt64);

    for (var i = 0; i < shape.length; i++) {
      inputShape[i] = shape[i];
    }

    final ptrVoid = inputTensorNative.cast<Void>();
    final status = createTensorWithDataAsOrtValue(
      inputTensorPointer,
      memoryInfo: memoryInfo,
      inputData: ptrVoid,
      inputDataLengthInBytes: values.length * sizeOfInt64,
      inputShape: inputShape,
      inputShapeLengthInBytes: inputShapeLengthInBytes,
      onnxTensorElementDataType:
          ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64.value,
    );
    if (status.isError) {
      final error =
          'Code: ${getErrorCodeMessage(status)}\n'
          'Message: ${consumeErrorMessage(status)}';
      calloc.free(inputTensorNative);
      calloc.free(inputShape);
      throw Exception(error);
    }
    calloc.free(inputShape);
    return inputTensorNative;
  }

  /// You MUST call [calloc.free] on the returned pointer when you are done with
  /// it, i.e. once inference is complete.
  Pointer<Int32> createInt32Tensor(
    Pointer<Pointer<OrtValue>> inputTensorPointer, {
    required Pointer<OrtMemoryInfo> memoryInfo,
    required List<int> values,
  }) {
    final sizeOfInt32 = sizeOf<Int32>();
    final inputTensorNative = calloc<Int32>(values.length * sizeOfInt32);
    for (var i = 0; i < values.length; i++) {
      inputTensorNative[i] = values[i];
    }
    final inputShape = calloc<Int64>(1 * sizeOf<Int64>());
    inputShape[0] = values.length;
    final ptrVoid = inputTensorNative.cast<Void>();
    final status = createTensorWithDataAsOrtValue(
      inputTensorPointer,
      memoryInfo: memoryInfo,
      inputData: ptrVoid,
      inputDataLengthInBytes: values.length * sizeOfInt32,
      inputShape: inputShape,
      inputShapeLengthInBytes: 1,
      onnxTensorElementDataType:
          ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_INT32.value,
    );
    if (status.isError) {
      final error =
          'Code: ${getErrorCodeMessage(status)}\n'
          'Message: ${consumeErrorMessage(status)}';
      calloc.free(inputTensorNative);
      calloc.free(inputShape);
      throw Exception(error);
    }
    calloc.free(inputShape);
    return inputTensorNative;
  }

  /// You MUST call [calloc.free] on the returned pointer when you are done with
  /// it, i.e. once inference is complete.
  Pointer<Uint8> createUint8Tensor(
    Pointer<Pointer<OrtValue>> inputTensorPointer, {
    required Pointer<OrtMemoryInfo> memoryInfo,
    required List<int> values,
  }) {
    final sizeOfUint8 = sizeOf<Uint8>();
    final inputTensorNative = calloc<Uint8>(values.length * sizeOfUint8);
    for (var i = 0; i < values.length; i++) {
      inputTensorNative[i] = values[i];
    }
    final inputShape = calloc<Int64>(2 * sizeOf<Int64>());
    inputShape[0] = 1;
    inputShape[1] = values.length;
    final status = createTensorWithDataAsOrtValue(
      inputTensorPointer,
      memoryInfo: memoryInfo,
      inputData: inputTensorNative.cast<Void>(),
      inputDataLengthInBytes: values.length * sizeOfUint8,
      inputShape: inputShape,
      inputShapeLengthInBytes: 2,
      onnxTensorElementDataType:
          ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT8.value,
    );
    if (status.isError) {
      final error =
          'Code: ${getErrorCodeMessage(status)}\n'
          'Message: ${consumeErrorMessage(status)}';
      calloc.free(inputTensorNative);
      calloc.free(inputShape);
      throw Exception(error);
    }
    calloc.free(inputShape);
    return inputTensorNative;
  }

  /// You MUST call [calloc.free] on the returned pointer.
  Pointer<Size> sessionGetOutputCount(Pointer<OrtSession> session) {
    final getOutputCountFn =
        SessionGetOutputCount.asFunction<
          Pointer<OrtStatus> Function(Pointer<OrtSession>, Pointer<Size>)
        >();
    final outputCount = calloc<Size>();
    final status = getOutputCountFn(session, outputCount);
    if (status.isError) {
      final error =
          'Code: ${getErrorCodeMessage(status)}\n'
          'Message: ${consumeErrorMessage(status)}';
      throw Exception(error);
    }
    return outputCount;
  }

  Pointer<OrtStatus> sessionGetOutputName(
    Pointer<OrtSession> session,
    int index,
    Pointer<Pointer<Char>> out,
  ) {
    final getFn =
        SessionGetOutputName.asFunction<
          Pointer<OrtStatus> Function(
            Pointer<OrtSession>,
            int,
            Pointer<OrtAllocator>,
            Pointer<Pointer<Char>>,
          )
        >();
    final allocator = calloc<Pointer<OrtAllocator>>();
    getAllocatorWithDefaultOptions(allocator);
    final status = getFn(session, index, allocator.value, out);
    calloc.free(allocator);
    if (status.isError) {
      final error =
          'Code: ${getErrorCodeMessage(status)}\n'
          'Message: ${consumeErrorMessage(status)}';
      throw Exception(error);
    }
    return status;
  }

  /// Must be freed [releaseRunOptions].
  Pointer<OrtStatus> createRunOptions(
    Pointer<Pointer<OrtRunOptions>> runOptions,
  ) {
    final createRunOptionsFn =
        CreateRunOptions.asFunction<
          Pointer<OrtStatus> Function(Pointer<Pointer<OrtRunOptions>>)
        >();
    final status = createRunOptionsFn(runOptions);
    if (status.isError) {
      final error =
          'Code: ${getErrorCodeMessage(status)}\n'
          'Message: ${consumeErrorMessage(status)}';
      throw Exception(error);
    }
    return status;
  }

  void releaseRunOptions(Pointer<OrtRunOptions> runOptions) {
    final releaseRunOptionsFn =
        ReleaseRunOptions.asFunction<void Function(Pointer<OrtRunOptions>)>();
    releaseRunOptionsFn(runOptions);
  }

  // [value] must be freed with [releaseValue].
  Pointer<OrtStatus> createTensorWithDataAsOrtValue(
    Pointer<Pointer<OrtValue>> value, {
    required Pointer<OrtMemoryInfo> memoryInfo,
    required Pointer<Void> inputData,
    required int inputDataLengthInBytes,
    required Pointer<Int64> inputShape,
    required int inputShapeLengthInBytes,
    required int onnxTensorElementDataType,
  }) {
    final createTensorWithDataFn =
        CreateTensorWithDataAsOrtValue.asFunction<
          Pointer<OrtStatus> Function(
            Pointer<OrtMemoryInfo>,
            Pointer<Void>,
            int,
            Pointer<Int64>,
            int,
            int,
            Pointer<Pointer<OrtValue>> out,
          )
        >();
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

  void releaseValue(Pointer<OrtValue> value) {
    final releaseValueFn =
        ReleaseValue.asFunction<void Function(Pointer<OrtValue>)>();
    releaseValueFn(value);
  }

  /// Must be freed with [releaseMemoryInfo].
  Pointer<OrtStatus> createCpuMemoryInfo(
    Pointer<Pointer<OrtMemoryInfo>> memoryInfo, {
    int ortAllocator = 3 /* OrtAllocatorType.OrtArenaAllocator */,
    int ortMemType = 0 /* OrtMemType.OrtMemTypeDefault */,
  }) {
    final createCpuMemoryInfoFn =
        CreateCpuMemoryInfo.asFunction<
          Pointer<OrtStatus> Function(int, int, Pointer<Pointer<OrtMemoryInfo>>)
        >();
    final status = createCpuMemoryInfoFn(ortAllocator, ortMemType, memoryInfo);
    if (status.isError) {
      final error =
          'Code: ${getErrorCodeMessage(status)}\n'
          'Message: ${consumeErrorMessage(status)}';
      throw Exception(error);
    }
    return status;
  }

  void releaseMemoryInfo(Pointer<OrtMemoryInfo> memoryInfo) {
    final releaseCpuMemoryInfoFn =
        ReleaseMemoryInfo.asFunction<void Function(Pointer<OrtMemoryInfo>)>();
    releaseCpuMemoryInfoFn(memoryInfo);
  }

  Pointer<OrtStatus> createEnv(
    Pointer<Pointer<OrtEnv>> env, {
    int logLevel = 3 /* OrtLoggingLevel.ORT_LOGGING_LEVEL_ERROR */,
    String logId = '',
  }) {
    final createEnvFn =
        CreateEnv.asFunction<
          Pointer<OrtStatus> Function(
            int,
            Pointer<Char>,
            Pointer<Pointer<OrtEnv>>,
          )
        >();
    final logIdChars = logId.toNativeUtf8().cast<Char>();
    try {
      final status = createEnvFn(
        logLevel,
        logIdChars,
        Pointer.fromAddress(env.address),
      );
      return status;
    } finally {
      malloc.free(logIdChars);
    }
  }

  void releaseEnv(Pointer<OrtEnv> env) {
    final releaseEnvFn =
        ReleaseEnv.asFunction<void Function(Pointer<OrtEnv>)>();
    releaseEnvFn(env);
  }

  Pointer<OrtStatus> createSession({
    required Pointer<OrtEnv> env,
    required String modelPath,
    required Pointer<OrtSessionOptions> sessionOptions,
    required Pointer<Pointer<OrtSession>> session,
  }) {
    final createSessionFn =
        CreateSession.asFunction<
          Pointer<OrtStatus> Function(
            Pointer<OrtEnv>,
            Pointer<Char>,
            Pointer<OrtSessionOptions>,
            Pointer<Pointer<OrtSession>>,
          )
        >();
    final modelPathChars = Platform.isWindows
        ? modelPath.toNativeUtf16().cast<Char>()
        : modelPath.toNativeUtf8().cast<Char>();
    try {
      final status = createSessionFn(
        env,
        modelPathChars,
        sessionOptions,
        session,
      );
      return status;
    } finally {
      malloc.free(modelPathChars);
    }
  }

  Pointer<OrtStatus> createSessionOptions(
    Pointer<Pointer<OrtSessionOptions>> optionsPtr,
  ) {
    final createSessionOptionsFn =
        CreateSessionOptions.asFunction<
          Pointer<OrtStatus> Function(Pointer<Pointer<OrtSessionOptions>>)
        >();
    final status = createSessionOptionsFn(optionsPtr);
    if (status.isError) {
      final error =
          'Code: ${getErrorCodeMessage(status)}\n'
          'Message: ${consumeErrorMessage(status)}';
      throw Exception(error);
    }
    return status;
  }

  void releaseSessionOptions(Pointer<OrtSessionOptions> sessionOptions) {
    final releaseSessionOptionsFn =
        ReleaseSessionOptions.asFunction<
          void Function(Pointer<OrtSessionOptions>)
        >();
    releaseSessionOptionsFn(sessionOptions);
  }

  void releaseSession(Pointer<OrtSession> session) {
    final releaseSessionFn =
        ReleaseSession.asFunction<void Function(Pointer<OrtSession>)>();
    releaseSessionFn(session);
  }

  // external ffi.Pointer<
  //   ffi.NativeFunction<
  //       OrtStatusPtr Function(ffi.Pointer<OrtValue> value, ffi.Size index,
  //           ffi.Pointer<ffi.Size> out)>> GetStringTensorElementLength;

  Pointer<OrtStatus> getStringTensorElementLength(
    Pointer<OrtValue> value,
    int index,
    Pointer<Size> out,
  ) {
    final getStringTensorElementLengthFn =
        GetStringTensorElementLength.asFunction<
          Pointer<OrtStatus> Function(Pointer<OrtValue>, int, Pointer<Size>)
        >();
    final status = getStringTensorElementLengthFn(value, index, out);
    if (status.isError) {
      final error =
          'Get string tensor element length failed. Code: ${getErrorCodeMessage(status)}\n'
          'Message: ${consumeErrorMessage(status)}';
      throw Exception(error);
    }
    return status;
  }

  Pointer<OrtStatus> getStringTensorElement(
    Pointer<OrtValue> value,
    int stringLength,
    int index,
    Pointer<Void> s,
  ) {
    final getStringTensorElementFn =
        GetStringTensorElement.asFunction<
          Pointer<OrtStatus> Function(
            Pointer<OrtValue>,
            int,
            int,
            Pointer<Void>,
          )
        >();
    final status = getStringTensorElementFn(value, stringLength, index, s);
    if (status.isError) {
      final error =
          'Get string tensor element failed. Code: ${getErrorCodeMessage(status)}\n'
          'Message: ${consumeErrorMessage(status)}';
      throw Exception(error);
    }
    return status;
  }

  Pointer<OrtStatus> getAllocatorWithDefaultOptions(
    Pointer<Pointer<OrtAllocator>> out,
  ) {
    final getAllocatorWithDefaultOptionsFn =
        GetAllocatorWithDefaultOptions.asFunction<
          Pointer<OrtStatus> Function(Pointer<Pointer<OrtAllocator>>)
        >();
    final status = getAllocatorWithDefaultOptionsFn(out);
    return status;
  }

  Pointer<OrtStatus> getTensorMutableData(
    Pointer<OrtValue> value,
    Pointer<Pointer<Void>> out,
  ) {
    final getTensorMutableDataFn =
        GetTensorMutableData.asFunction<
          Pointer<OrtStatus> Function(Pointer<OrtValue>, Pointer<Pointer<Void>>)
        >();
    final status = getTensorMutableDataFn(value, out);
    if (status.isError) {
      final error =
          'Get tensor data failed. Code: ${getErrorCodeMessage(status)}\n'
          'Message: ${consumeErrorMessage(status)}';
      throw Exception(error);
    }
    return status;
  }

  Pointer<OrtStatus> getDimensionsCount(
    Pointer<OrtTensorTypeAndShapeInfo> info,
    Pointer<Size> out,
  ) {
    final getDimensionsCountFn =
        GetDimensionsCount.asFunction<
          Pointer<OrtStatus> Function(
            Pointer<OrtTensorTypeAndShapeInfo>,
            Pointer<Size>,
          )
        >();

    final status = getDimensionsCountFn(info, out);
    if (status.isError) {
      final error =
          'Get dimensions count failed. Code: ${getErrorCodeMessage(status)}\n'
          'Message: ${consumeErrorMessage(status)}';
      throw Exception(error);
    }
    return status;
  }

  /// Call [releaseTensorTypeAndShapeInfo] on the returned pointer when you are
  /// done with it.
  Pointer<OrtStatus> getTensorTypeAndShape(
    Pointer<OrtValue> value,
    Pointer<Pointer<OrtTensorTypeAndShapeInfo>> out,
  ) {
    final getTensorTypeAndShapeFn =
        GetTensorTypeAndShape.asFunction<
          Pointer<OrtStatus> Function(
            Pointer<OrtValue>,
            Pointer<Pointer<OrtTensorTypeAndShapeInfo>>,
          )
        >();
    final status = getTensorTypeAndShapeFn(value, out);
    if (status.isError) {
      final error =
          'Get tensor type and shape failed. Code: ${getErrorCodeMessage(status)}\n'
          'Message: ${consumeErrorMessage(status)}';
      throw Exception(error);
    }
    return status;
  }

  void releaseTensorTypeAndShapeInfo(Pointer<OrtTensorTypeAndShapeInfo> info) {
    final releaseTensorTypeAndShapeInfoFn =
        ReleaseTensorTypeAndShapeInfo.asFunction<
          void Function(Pointer<OrtTensorTypeAndShapeInfo>)
        >();
    releaseTensorTypeAndShapeInfoFn(info);
  }

  Pointer<OrtStatus> getTensorElementType(
    Pointer<OrtTensorTypeAndShapeInfo> info,
    Pointer<UnsignedInt> out,
  ) {
    final getTensorElementTypeFn =
        GetTensorElementType.asFunction<
          OrtStatusPtr Function(
            Pointer<OrtTensorTypeAndShapeInfo>,
            Pointer<UnsignedInt>,
          )
        >();
    final status = getTensorElementTypeFn(info, out);
    if (status.isError) {
      final error =
          'Get tensor element type failed. Code: ${getErrorCodeMessage(status)}\n'
          'Message: ${consumeErrorMessage(status)}';
      throw Exception(error);
    }
    return status;
  }

  Pointer<OrtStatus> getTensorShapeElementCount(
    Pointer<OrtTensorTypeAndShapeInfo> info,
    Pointer<Size> out,
  ) {
    final getTensorShapeElementCountFn =
        GetTensorShapeElementCount.asFunction<
          Pointer<OrtStatus> Function(
            Pointer<OrtTensorTypeAndShapeInfo>,
            Pointer<Size>,
          )
        >();
    final status = getTensorShapeElementCountFn(info, out);
    if (status.isError) {
      final error =
          'Get tensor shape element count failed. Code: ${getErrorCodeMessage(status)}\n'
          'Message: ${consumeErrorMessage(status)}';
      throw Exception(error);
    }
    return status;
  }

  Pointer<OrtStatus> registerCustomOpsLibrary(
    Pointer<OrtSessionOptions> options,
    Pointer<Char> libraryPath,
    Pointer<Pointer<Void>> libraryHandle,
  ) {
    final registerCustomOpsLibraryFn =
        RegisterCustomOpsLibrary.asFunction<
          Pointer<OrtStatus> Function(
            Pointer<OrtSessionOptions>,
            Pointer<Char>,
            Pointer<Pointer<Void>> libraryHandle,
          )
        >();
    final status = registerCustomOpsLibraryFn(
      options,
      libraryPath,
      libraryHandle,
    );
    if (status.isError) {
      final error =
          'Register custom ops library failed. Code: ${getErrorCodeMessage(status)}\n'
          'Message: ${consumeErrorMessage(status)}';
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
    final runFn =
        Run.asFunction<
          Pointer<OrtStatus> Function(
            Pointer<OrtSession>,
            Pointer<OrtRunOptions>,
            Pointer<Pointer<Char>>,
            Pointer<Pointer<OrtValue>>,
            int,
            Pointer<Pointer<Char>>,
            int,
            Pointer<Pointer<OrtValue>>,
          )
        >();
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
      final error =
          'Run failed. Code: ${getErrorCodeMessage(status)}\n'
          'Message: ${consumeErrorMessage(status)}';
      // rationale: Crucial for debugging, for some reason this
      // isn't bubbling to UI.
      // TODO: figure out why
      // ignore: avoid_print
      print('ONNX run result is an error. Error: $error');
      throw Exception(error);
    }
    return status;
  }

  Pointer<OrtStatus> addSessionConfigEntry(
    Pointer<OrtSessionOptions> options, {
    required String key,
    required String value,
  }) {
    final fn =
        AddSessionConfigEntry.asFunction<
          Pointer<OrtStatus> Function(
            Pointer<OrtSessionOptions>,
            Pointer<Char>,
            Pointer<Char>,
          )
        >();
    final nativeKey = key.toNativeUtf8();
    final nativeValue = value.toNativeUtf8();
    try {
      final status = fn(
        options,
        nativeKey.cast<Char>(),
        nativeValue.cast<Char>(),
      );
      if (status.isError) {
        final error =
            'AddSessionConfigEntry failed for $key. '
            'Code: ${getErrorCodeMessage(status)}\n'
            'Message: ${consumeErrorMessage(status)}';
        throw Exception(error);
      }
      return status;
    } finally {
      malloc.free(nativeValue);
      malloc.free(nativeKey);
    }
  }

  Pointer<OrtStatus> setIntraOpNumThreads(
    Pointer<OrtSessionOptions> options,
    int intraOpNumThreads,
  ) {
    final fn =
        SetIntraOpNumThreads.asFunction<
          Pointer<OrtStatus> Function(Pointer<OrtSessionOptions>, int)
        >();
    final status = fn(options, intraOpNumThreads);
    if (status.isError) {
      final error =
          'SessionOptionsSetIntraOpNumThreads failed. Code: ${getErrorCodeMessage(status)}\n'
          'Message: ${consumeErrorMessage(status)}';
      throw Exception(error);
    }
    return status;
  }

  Pointer<OrtStatus> setInterOpNumThreads(
    Pointer<OrtSessionOptions> options,
    int interOpNumThreads,
  ) {
    final fn =
        SetInterOpNumThreads.asFunction<
          Pointer<OrtStatus> Function(Pointer<OrtSessionOptions>, int)
        >();
    final status = fn(options, interOpNumThreads);
    if (status.isError) {
      final error =
          'SessionOptionsSetInterOpNumThreads failed. Code: ${getErrorCodeMessage(status)}\n'
          'Message: ${consumeErrorMessage(status)}';
      throw Exception(error);
    }
    return status;
  }
}

/// This is a wrapper for FFI bindings that define a running model.
///
/// The sessionPtr is live. If you free it, you will not be able to use the
/// model anymore. Conversely, you must free it when you are done with it.
class OrtSessionObjects implements Finalizable {
  final Pointer<Pointer<OrtSession>> sessionPtr;
  final Pointer<Pointer<OrtEnv>> envPtr;
  final OrtApiBase apiBase;
  final OrtApi api;
  final Pointer<_OrtSessionFinalizerContext> _finalizerContext;
  bool _released = false;

  OrtSessionObjects._({
    required this.sessionPtr,
    required this.envPtr,
    required this.apiBase,
    required this.api,
    required Pointer<_OrtSessionFinalizerContext> finalizerContext,
  }) : _finalizerContext = finalizerContext {
    // NativeFinalizer callbacks run during isolate-group shutdown, including
    // Flutter hot restart. This is the fallback for cases where the isolate
    // cannot process its normal explicit `close` message.
    _ortSessionFinalizer.attach(this, _finalizerContext.cast(), detach: this);
  }

  void release() {
    if (_released) return;
    _released = true;
    _ortSessionFinalizer.detach(this);
    _releaseOrtSessionContext(_finalizerContext.cast());
  }
}

void releaseOrtSessionObjects(OrtSessionObjects? objects) {
  if (objects == null) {
    return;
  }

  objects.release();
}

/// You MUST call [calloc.free] on the returned pointer when you are done with it.
///
/// It is reasonable to never free it in an app where you would like the model
/// to be loaded for the lifetime of the app.
/// Creates an ORT session from [modelPath].
///
/// [sessionConfigEntries] is a narrow escape hatch for documented ORT runtime
/// workarounds. Entries are copied into the session options before creation.
OrtSessionObjects createOrtSession(
  String modelPath, {
  bool includeOnnxExtensionsOps = false,
  Map<String, String> sessionConfigEntries = const {},
}) {
  // Normal builds resolve the hook's code asset through @Native. The explicit
  // lookup exists only for diagnostic hosts that intentionally override ORT.
  final answer = switch (fonnxOrtDylibPathOverride) {
    final path? =>
      DynamicLibrary.open(path).lookupFunction<
        Pointer<OrtApiBase> Function(),
        Pointer<OrtApiBase> Function()
      >('OrtGetApiBase')(),
    null => OrtGetApiBase(),
  };
  final baseApi = answer.ref;
  final api = baseApi.GetApi.asFunction<Pointer<OrtApi> Function(int)>();
  final ortApiPointer = api(ORT_API_VERSION);
  if (ortApiPointer == nullptr) {
    throw StateError('ONNX Runtime does not support API $ORT_API_VERSION');
  }
  final ortApi = ortApiPointer.ref;
  final envPtr = calloc<Pointer<OrtEnv>>();
  final sessionOptionsPtr = calloc<Pointer<OrtSessionOptions>>();
  final sessionPtr = calloc<Pointer<OrtSession>>();
  var optionsPointerFreed = false;
  var ownershipTransferred = false;

  try {
    final status = ortApi.createEnv(envPtr);
    if (status.isError) {
      final error =
          'Code: ${ortApi.getErrorCodeMessage(status)}\n'
          'Message: ${ortApi.consumeErrorMessage(status)}';
      throw Exception(error);
    }

    ortApi.createSessionOptions(sessionOptionsPtr);
    for (final entry in sessionConfigEntries.entries) {
      ortApi.addSessionConfigEntry(
        sessionOptionsPtr.value,
        key: entry.key,
        value: entry.value,
      );
    }
    if (includeOnnxExtensionsOps) {
      final extensionsStatus = registerOrtExtensions(
        options: sessionOptionsPtr.value,
        apiBase: answer,
        libraryPathOverride: fonnxOrtExtensionsDylibPathOverride,
      );
      if (extensionsStatus.isError) {
        final error =
            'Register custom ops failed. '
            'Code: ${ortApi.getErrorCodeMessage(extensionsStatus)}\n'
            'Message: ${ortApi.consumeErrorMessage(extensionsStatus)}';
        throw Exception(error);
      }
    }

    // Avoiding explicit inter/intra-op thread counts currently performs best.
    // CoreML was also measured around 10x slower than CPU on an M2 Max for the
    // package's embedding graphs, so provider selection remains ORT's default.
    final sessionStatus = ortApi.createSession(
      env: envPtr.value,
      modelPath: modelPath,
      sessionOptions: sessionOptionsPtr.value,
      session: sessionPtr,
    );
    if (sessionStatus.isError) {
      final error =
          'Code: ${ortApi.getErrorCodeMessage(sessionStatus)}\n'
          'Message: ${ortApi.consumeErrorMessage(sessionStatus)}';
      throw Exception(error);
    }

    ortApi.releaseSessionOptions(sessionOptionsPtr.value);
    sessionOptionsPtr.value = nullptr;
    calloc.free(sessionOptionsPtr);
    optionsPointerFreed = true;

    final finalizerContext = calloc<_OrtSessionFinalizerContext>();
    finalizerContext.ref
      ..session = sessionPtr
      ..env = envPtr
      ..releaseSession = ortApi.ReleaseSession
      ..releaseEnv = ortApi.ReleaseEnv;
    ownershipTransferred = true;
    debugPrint('ORT Session created');
    return OrtSessionObjects._(
      sessionPtr: sessionPtr,
      envPtr: envPtr,
      apiBase: baseApi,
      api: ortApi,
      finalizerContext: finalizerContext,
    );
  } catch (_) {
    if (sessionPtr.value != nullptr) {
      ortApi.releaseSession(sessionPtr.value);
      sessionPtr.value = nullptr;
    }
    if (!optionsPointerFreed && sessionOptionsPtr.value != nullptr) {
      ortApi.releaseSessionOptions(sessionOptionsPtr.value);
      sessionOptionsPtr.value = nullptr;
    }
    if (envPtr.value != nullptr) {
      ortApi.releaseEnv(envPtr.value);
      envPtr.value = nullptr;
    }
    rethrow;
  } finally {
    if (!ownershipTransferred) {
      calloc.free(sessionPtr);
      if (!optionsPointerFreed) calloc.free(sessionOptionsPtr);
      calloc.free(envPtr);
    }
  }
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
