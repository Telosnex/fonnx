import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:fonnx/onnx/ort.dart';
import 'package:fonnx/onnx/ort_ffi_bindings.dart' hide calloc, free, malloc;

/// One ORT session, with helpers that create, run, and release tensors.
final class OrtSessionGraph {
  OrtSessionGraph(
    String path, {
    Map<String, String> sessionConfigEntries = const {},
  }) : _session = createOrtSession(
         path,
         sessionConfigEntries: sessionConfigEntries,
       );

  final OrtSessionObjects _session;
  var _closed = false;

  OwnedOrtValue floatTensor(Float32List values, List<int> shape) {
    final data = calloc<Float>(values.length);
    data.asTypedList(values.length).setAll(0, values);
    return _tensor(
      data: data.cast<Void>(),
      byteLength: values.length * sizeOf<Float>(),
      shape: shape,
      type: ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT.value,
      backing: data.cast<Void>(),
    );
  }

  OwnedOrtValue zeroFloatTensor(List<int> shape) {
    final count = shape.fold<int>(1, (total, dimension) => total * dimension);
    // calloc of 0 bytes may return null; ORT needs a valid pointer.
    final data = calloc<Float>(count == 0 ? 1 : count);
    return _tensor(
      data: data.cast<Void>(),
      byteLength: count * sizeOf<Float>(),
      shape: shape,
      type: ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT.value,
      backing: data.cast<Void>(),
    );
  }

  OwnedOrtValue int64Tensor(Int64List values, List<int> shape) {
    final data = calloc<Int64>(values.length);
    data.asTypedList(values.length).setAll(0, values);
    return _tensor(
      data: data.cast<Void>(),
      byteLength: values.length * sizeOf<Int64>(),
      shape: shape,
      type: ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64.value,
      backing: data.cast<Void>(),
    );
  }

  OwnedOrtValue int32Tensor(Int32List values, List<int> shape) {
    final data = calloc<Int32>(values.length);
    data.asTypedList(values.length).setAll(0, values);
    return _tensor(
      data: data.cast<Void>(),
      byteLength: values.length * sizeOf<Int32>(),
      shape: shape,
      type: ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_INT32.value,
      backing: data.cast<Void>(),
    );
  }

  OwnedOrtValue zeroInt64Tensor(List<int> shape) {
    final count = shape.fold<int>(1, (total, dimension) => total * dimension);
    final data = calloc<Int64>(count);
    return _tensor(
      data: data.cast<Void>(),
      byteLength: count * sizeOf<Int64>(),
      shape: shape,
      type: ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64.value,
      backing: data.cast<Void>(),
    );
  }

  OwnedOrtValue boolTensor(List<bool> values, List<int> shape) {
    final data = calloc<Uint8>(values.length);
    for (var i = 0; i < values.length; i++) {
      data[i] = values[i] ? 1 : 0;
    }
    return _tensor(
      data: data.cast<Void>(),
      byteLength: values.length,
      shape: shape,
      type: ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_BOOL.value,
      backing: data.cast<Void>(),
    );
  }

  /// Takes ownership of [data], which holds [count] floats, as a tensor.
  ///
  /// [data] must come from `calloc`. It is freed when the value is released.
  OwnedOrtValue adoptFloatBuffer(
    Pointer<Float> data,
    int count,
    List<int> shape,
  ) {
    return _tensor(
      data: data.cast<Void>(),
      byteLength: count * sizeOf<Float>(),
      shape: shape,
      type: ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT.value,
      backing: data.cast<Void>(),
    );
  }

  /// The float data of [value]. It is valid until [value] is released.
  Float32List floatData(Pointer<OrtValue> value) {
    final data = calloc<Pointer<Void>>();
    final shape = calloc<Pointer<OrtTensorTypeAndShapeInfo>>();
    final count = calloc<Size>();
    try {
      _session.api.getTensorMutableData(value, data);
      _session.api.getTensorTypeAndShape(value, shape);
      _session.api.getTensorShapeElementCount(shape.value, count);
      return data.value.cast<Float>().asTypedList(count.value);
    } finally {
      if (shape.value.address != 0) {
        _session.api.releaseTensorTypeAndShapeInfo(shape.value);
      }
      calloc.free(count);
      calloc.free(shape);
      calloc.free(data);
    }
  }

  OwnedOrtValue _tensor({
    required Pointer<Void> data,
    required int byteLength,
    required List<int> shape,
    required int type,
    required Pointer<Void> backing,
  }) {
    final value = calloc<Pointer<OrtValue>>();
    final memoryInfo = calloc<Pointer<OrtMemoryInfo>>();
    final nativeShape = calloc<Int64>(shape.length);
    try {
      for (var i = 0; i < shape.length; i++) {
        nativeShape[i] = shape[i];
      }
      _session.api.createCpuMemoryInfo(memoryInfo);
      final status = _session.api.createTensorWithDataAsOrtValue(
        value,
        memoryInfo: memoryInfo.value,
        inputData: data,
        inputDataLengthInBytes: byteLength,
        inputShape: nativeShape,
        inputShapeLengthInBytes: shape.length,
        onnxTensorElementDataType: type,
      );
      if (status.isError) {
        throw Exception(_session.api.consumeErrorMessage(status));
      }
      return OwnedOrtValue(this, value.value, backing: backing);
    } catch (_) {
      calloc.free(backing);
      rethrow;
    } finally {
      if (memoryInfo.value.address != 0) {
        _session.api.releaseMemoryInfo(memoryInfo.value);
      }
      calloc.free(nativeShape);
      calloc.free(memoryInfo);
      calloc.free(value);
    }
  }

  List<Pointer<OrtValue>> run({
    required List<String> inputNames,
    required List<Pointer<OrtValue>> inputValues,
    required List<String> outputNames,
  }) {
    if (_closed) throw StateError('ORT graph is closed');
    final nativeInputNames = calloc<Pointer<Char>>(inputNames.length);
    final nativeInputValues = calloc<Pointer<OrtValue>>(inputValues.length);
    final nativeOutputNames = calloc<Pointer<Char>>(outputNames.length);
    final nativeOutputValues = calloc<Pointer<OrtValue>>(outputNames.length);
    final runOptions = calloc<Pointer<OrtRunOptions>>();
    final allocatedNames = <Pointer<Utf8>>[];
    try {
      for (var i = 0; i < inputNames.length; i++) {
        final name = inputNames[i].toNativeUtf8();
        allocatedNames.add(name);
        nativeInputNames[i] = name.cast<Char>();
        nativeInputValues[i] = inputValues[i];
      }
      for (var i = 0; i < outputNames.length; i++) {
        final name = outputNames[i].toNativeUtf8();
        allocatedNames.add(name);
        nativeOutputNames[i] = name.cast<Char>();
      }
      _session.api.createRunOptions(runOptions);
      _session.api.run(
        session: _session.sessionPtr.value,
        runOptions: runOptions.value,
        inputNames: nativeInputNames,
        inputValues: nativeInputValues,
        inputCount: inputValues.length,
        outputNames: nativeOutputNames,
        outputCount: outputNames.length,
        outputValues: nativeOutputValues,
      );
      return List<Pointer<OrtValue>>.generate(
        outputNames.length,
        (index) => nativeOutputValues[index],
        growable: false,
      );
    } catch (_) {
      for (var i = 0; i < outputNames.length; i++) {
        if (nativeOutputValues[i].address != 0) {
          releaseValue(nativeOutputValues[i]);
        }
      }
      rethrow;
    } finally {
      if (runOptions.value.address != 0) {
        _session.api.releaseRunOptions(runOptions.value);
      }
      for (final name in allocatedNames) {
        malloc.free(name);
      }
      calloc.free(runOptions);
      calloc.free(nativeOutputValues);
      calloc.free(nativeOutputNames);
      calloc.free(nativeInputValues);
      calloc.free(nativeInputNames);
    }
  }

  Float32List copyFloatTensor(Pointer<OrtValue> value) =>
      Float32List.fromList(floatData(value));

  void releaseValue(Pointer<OrtValue> value) =>
      _session.api.releaseValue(value);

  void close() {
    if (_closed) return;
    _closed = true;
    releaseOrtSessionObjects(_session);
  }
}

/// An ORT value and the native buffer that backs it, if any.
final class OwnedOrtValue {
  OwnedOrtValue(this.owner, this.value, {this.backing});

  final OrtSessionGraph owner;
  final Pointer<OrtValue> value;
  final Pointer<Void>? backing;
  var _released = false;

  void release() {
    if (_released) return;
    _released = true;
    owner.releaseValue(value);
    final data = backing;
    if (data != null) {
      calloc.free(data);
    }
  }
}
