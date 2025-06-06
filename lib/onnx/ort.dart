import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:fonnx/dylib_path_overrides.dart';
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
      final error = 'Code: ${getErrorCodeMessage(status)}\n'
          'Message: ${getErrorMessage(status)}';
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
      final error = 'Code: ${getErrorCodeMessage(status)}\n'
          'Message: ${getErrorMessage(status)}';
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
      final error = 'Code: ${getErrorCodeMessage(status)}\n'
          'Message: ${getErrorMessage(status)}';
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
        .first.first.length; // Columns: Number of columns in the first row

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
      final error = 'Code: ${getErrorCodeMessage(status)}\n'
          'Message: ${getErrorMessage(status)}';
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
      final error = 'Code: ${getErrorCodeMessage(status)}\n'
          'Message: ${getErrorMessage(status)}';
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
      final error = 'Code: ${getErrorCodeMessage(status)}\n'
          'Message: ${getErrorMessage(status)}';
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
      Pointer<Pointer<OrtValue>> inputTensorPointer,
      {required Pointer<OrtMemoryInfo> memoryInfo,
      required List<int> values}) {
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
      final error = 'Code: ${getErrorCodeMessage(status)}\n'
          'Message: ${getErrorMessage(status)}';
      calloc.free(inputTensorNative);
      calloc.free(inputShape);
      throw Exception(error);
    }
    calloc.free(inputShape);
    return inputTensorNative;
  }

  /// You MUST call [calloc.free] on the returned pointer.
  Pointer<Size> sessionGetOutputCount(Pointer<OrtSession> session) {
    final getOutputCountFn = SessionGetOutputCount.asFunction<
        Pointer<OrtStatus> Function(
          Pointer<OrtSession>,
          Pointer<Size>,
        )>();
    final outputCount = calloc<Size>();
    final status = getOutputCountFn(session, outputCount);
    if (status.isError) {
      final error = 'Code: ${getErrorCodeMessage(status)}\n'
          'Message: ${getErrorMessage(status)}';
      throw Exception(error);
    }
    return outputCount;
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
    calloc.free(allocator);
    if (status.isError) {
      final error = 'Code: ${getErrorCodeMessage(status)}\n'
          'Message: ${getErrorMessage(status)}';
      throw Exception(error);
    }
    return status;
  }

  /// Must be freed [releaseRunOptions].
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
    final modelPathChars =
        defaultTargetPlatform == TargetPlatform.windows || Platform.isWindows
            ? modelPath.toNativeUtf16().cast<Char>()
            : modelPath.toNativeUtf8().cast<Char>();
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
            Pointer<OrtStatus> Function(
                Pointer<OrtValue>, int, Pointer<Size>)>();
    final status = getStringTensorElementLengthFn(value, index, out);
    if (status.isError) {
      final error =
          'Get string tensor element length failed. Code: ${getErrorCodeMessage(status)}\n'
          'Message: ${getErrorMessage(status)}';
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
    final getStringTensorElementFn = GetStringTensorElement.asFunction<
        Pointer<OrtStatus> Function(
            Pointer<OrtValue>, int, int, Pointer<Void>)>();
    final status = getStringTensorElementFn(value, stringLength, index, s);
    if (status.isError) {
      final error =
          'Get string tensor element failed. Code: ${getErrorCodeMessage(status)}\n'
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

  Pointer<OrtStatus> getDimensionsCount(
    Pointer<OrtTensorTypeAndShapeInfo> info,
    Pointer<Size> out,
  ) {
    final getDimensionsCountFn = GetDimensionsCount.asFunction<
        Pointer<OrtStatus> Function(
            Pointer<OrtTensorTypeAndShapeInfo>, Pointer<Size>)>();

    final status = getDimensionsCountFn(info, out);
    if (status.isError) {
      final error =
          'Get dimensions count failed. Code: ${getErrorCodeMessage(status)}\n'
          'Message: ${getErrorMessage(status)}';
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

  void releaseTensorTypeAndShapeInfo(
    Pointer<OrtTensorTypeAndShapeInfo> info,
  ) {
    final releaseTensorTypeAndShapeInfoFn = ReleaseTensorTypeAndShapeInfo
        .asFunction<void Function(Pointer<OrtTensorTypeAndShapeInfo>)>();
    releaseTensorTypeAndShapeInfoFn(info);
  }

  Pointer<OrtStatus> getTensorElementType(
    Pointer<OrtTensorTypeAndShapeInfo> info,
    Pointer<UnsignedInt> out,
  ) {
    final getTensorElementTypeFn = GetTensorElementType.asFunction<
        OrtStatusPtr Function(
            Pointer<OrtTensorTypeAndShapeInfo>, Pointer<UnsignedInt>)>();
    final status = getTensorElementTypeFn(info, out);
    if (status.isError) {
      final error =
          'Get tensor element type failed. Code: ${getErrorCodeMessage(status)}\n'
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

  Pointer<OrtStatus> registerCustomOpsLibrary(
    Pointer<OrtSessionOptions> options,
    Pointer<Char> libraryPath,
    Pointer<Pointer<Void>> libraryHandle,
  ) {
    final registerCustomOpsLibraryFn = RegisterCustomOpsLibrary.asFunction<
        Pointer<OrtStatus> Function(Pointer<OrtSessionOptions>, Pointer<Char>,
            Pointer<Pointer<Void>> libraryHandle)>();
    final status = registerCustomOpsLibraryFn(
      options,
      libraryPath,
      libraryHandle,
    );
    if (status.isError) {
      final error =
          'Register custom ops library failed. Code: ${getErrorCodeMessage(status)}\n'
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
      // rationale: Crucial for debugging, for some reason this
      // isn't bubbling to UI.
      // TODO: figure out why
      // ignore: avoid_print
      print('ONNX run result is an error. Error: $error');
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

/// This is a wrapper for FFI bindings that define a running model.
///
/// The sessionPtr is live. If you free it, you will not be able to use the
/// model anymore. Conversely, you must free it when you are done with it.
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

String get ortDylibPath {
  if (fonnxOrtDylibPathOverride != null) {
    return fonnxOrtDylibPathOverride!;
  }
  final isTesting = !kIsWeb && Platform.environment['FLUTTER_TEST'] == 'true';
  if (isTesting) {
    // defaultTargetPlatform is _always_ Android when running tests, so we need
    // to query the "actual" platform
    if (Platform.isWindows) {
      return 'windows/onnx_runtime/onnxruntime-x64.dll';
    } else if (Platform.isMacOS) {
      return 'macos/onnx_runtime/osx/libonnxruntime.1.16.1.dylib';
    } else if (Platform.isLinux) {
      return 'linux/onnx_runtime/libonnxruntime.so.1.16.1';
    } else {
      throw 'Unsure how to load ORT during testing for this platform (${Platform.operatingSystem})';
    }
  }
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      throw 'Android runs using a platform-specific implementation, not FFI';
    case TargetPlatform.fuchsia:
      throw UnimplementedError();
    case TargetPlatform.iOS:
      throw 'iOS runs using a platform-specific implementation, not FFI';
    case TargetPlatform.linux:
      return 'libonnxruntime.so.1.16.1';
    case TargetPlatform.macOS:
      return 'libonnxruntime.1.16.1.dylib';
    case TargetPlatform.windows:
      return 'onnxruntime-x64.dll';
  }
}

String get ortExtensionsDylibPath {
  if (fonnxOrtExtensionsDylibPathOverride != null) {
    return fonnxOrtExtensionsDylibPathOverride!;
  }
  final isTesting = !kIsWeb && Platform.environment['FLUTTER_TEST'] == 'true';
  if (isTesting) {
    if (Platform.isMacOS) {
      return 'macos/onnx_runtime/osx/libortextensions.0.9.0.dylib';
    } else if (Platform.isLinux) {
      return 'linux/onnx_runtime/libortextensions.so.0.9.0';
    } else {
      throw 'Unsure how to load ORT during testing for this platform (${Platform.operatingSystem})';
    }
  }
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      throw UnimplementedError();
    case TargetPlatform.fuchsia:
      throw UnimplementedError();
    case TargetPlatform.iOS:
      throw UnimplementedError();
    case TargetPlatform.linux:
      return 'libortextensions.so.0.9.0';
    case TargetPlatform.macOS:
      return 'libortextensions.0.9.0.dylib';
    case TargetPlatform.windows:
      return 'ortextensions-x64.dll';
  }
}

/// You MUST call [calloc.free] on the returned pointer when you are done with it.
///
/// It is reasonable to never free it in an app where you would like the model
/// to be loaded for the lifetime of the app.
OrtSessionObjects createOrtSession(String modelPath,
    {bool includeOnnxExtensionsOps = false}) {
  // Used to have:
  //   DynamicLibrary.open(dylibPath);
  //   final baseApi = OrtGetApiBase().ref;
  // That led to an error that said:
  //
  // After reading [this Github issue](https://github.com/dart-lang/sdk/issues/50551)
  //   my instinct was there may be an issue with global static functions and ffi,
  //   and Linux may be lagging in support. Explicitly looking the function up in
  //   the explicit library did fix it.
  final lib = DynamicLibrary.open(ortDylibPath);

  final fn = lib.lookupFunction<Pointer<OrtApiBase> Function(),
      Pointer<OrtApiBase> Function()>('OrtGetApiBase');
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
  ortApi.createSessionOptions(sessionOptionsPtr);
  if (includeOnnxExtensionsOps) {
    try {
      DynamicLibrary.open(ortExtensionsDylibPath);
      final libraryHandle = calloc<Pointer<Void>>();
      final utf8Path = ortExtensionsDylibPath.toNativeUtf8().cast<Char>();
      ortApi.registerCustomOpsLibrary(
          sessionOptionsPtr.value, utf8Path, libraryHandle);
    } catch (e) {
      debugPrint('Error loading ORT Extensions: $e');
      rethrow;
    }
  }

  // Avoiding setting inter/intra op num threads at all seems to get the best performance.
  // 128 threads: ~5.00 ms/embedding
  // 1 thread: ~0.85 ms/embedding
  // 7 threads: ~0.65 ms/embedding
  // Not setting inter/intra op num threads: ~0.65 ms/embedding

  // Adding CoreML support slowed down inference about 10x on M2 Max.
  // This persisted even when CPU only + only if ANE is available flags were
  // set, either together or independently.
  final sessionPtr = calloc<Pointer<OrtSession>>();
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
  debugPrint('ORT Session created');
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
