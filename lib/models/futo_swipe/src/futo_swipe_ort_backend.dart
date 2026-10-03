import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:fonnx/onnx/ort.dart';
import 'package:fonnx/onnx/ort_ffi_bindings.dart' hide calloc, free, malloc;

import '../futo_swipe_types.dart';

/// Native ONNX Runtime backend. Use from one isolate at a time.
final class NativeFutoSwipeOnnxBackend implements FutoSwipeOnnxBackend {
  NativeFutoSwipeOnnxBackend(FutoSwipeBundle bundle)
    : _embeddingsPath = bundle.embeddingsPath {
    final graphs = <_OrtGraph>[];
    try {
      _encoder = _OrtGraph(bundle.encoderPath);
      graphs.add(_encoder);
      _decoder = _OrtGraph(bundle.decoderPath);
      graphs.add(_decoder);
      _context = _OrtGraph(bundle.contextModelPath);
    } catch (_) {
      for (final graph in graphs) {
        graph.close();
      }
      rethrow;
    }
  }

  final String _embeddingsPath;
  late final _OrtGraph _encoder;
  late final _OrtGraph _decoder;
  late final _OrtGraph _context;
  var _closed = false;

  @override
  Future<FutoEncoderOutput> runEncoder(
    Float32List features,
    Float32List layoutKeys,
    Uint8List layoutMask,
  ) async {
    _ensureOpen();
    final outputs = _encoder.run(
      [
        _Input.float('features', features, const [1, 2, 64]),
        _Input.float('layout_keys', layoutKeys, const [1, 64, 2]),
        _Input.bool('layout_mask', layoutMask, const [1, 64]),
      ],
      const ['log_emissions', 'coefficients', 'intention'],
    );
    return FutoEncoderOutput(
      logEmissions: outputs[0],
      coefficients: outputs[1],
      intention: outputs[2],
    );
  }

  @override
  Future<Float32List> runDecoder(Float32List features) async {
    _ensureOpen();
    return _decoder
        .run(
          [
            _Input.float('features', features, const [1, 32, 92]),
          ],
          const ['log_emissions'],
        )
        .single;
  }

  @override
  Future<Float32List> runContext(
    Int32List tokenIds,
    Int32List hashBuckets,
  ) async {
    _ensureOpen();
    return _context
        .run(
          [
            _Input.int64('token_ids', tokenIds, const [1, 16]),
            _Input.int64('hash_buckets', hashBuckets, const [1, 16, 2]),
          ],
          const ['context_states'],
        )
        .single;
  }

  @override
  Future<FutoContextEmbeddings> loadEmbeddings() async {
    _ensureOpen();
    // The tables are constants; keep the copies, not the session.
    final graph = _OrtGraph(_embeddingsPath);
    try {
      final tables = graph.run(const [], const [
        'exact_embeddings',
        'exact_biases',
        'hashed_embeddings',
        'hashed_biases',
      ]);
      return FutoContextEmbeddings(
        exactEmbeddings: tables[0],
        exactBiases: tables[1],
        hashedEmbeddings: tables[2],
        hashedBiases: tables[3],
      );
    } finally {
      graph.close();
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _encoder.close();
    _decoder.close();
    _context.close();
  }

  void _ensureOpen() {
    if (_closed) throw StateError('FUTO Swipe ONNX backend is closed');
  }
}

final class _Input {
  _Input._(this.name, this.data, this.byteLength, this.shape, this.type);

  factory _Input.float(String name, Float32List values, List<int> shape) {
    final data = calloc<Float>(values.length);
    data.asTypedList(values.length).setAll(0, values);
    return _Input._(
      name,
      data.cast(),
      values.length * sizeOf<Float>(),
      shape,
      ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT.value,
    );
  }

  /// Widens [values] to an int64 tensor.
  factory _Input.int64(String name, Int32List values, List<int> shape) {
    final data = calloc<Int64>(values.length);
    data.asTypedList(values.length).setAll(0, values);
    return _Input._(
      name,
      data.cast(),
      values.length * sizeOf<Int64>(),
      shape,
      ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64.value,
    );
  }

  factory _Input.bool(String name, Uint8List values, List<int> shape) {
    final data = calloc<Uint8>(values.length);
    data.asTypedList(values.length).setAll(0, values);
    return _Input._(
      name,
      data.cast(),
      values.length,
      shape,
      ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_BOOL.value,
    );
  }

  final String name;
  final Pointer<Void> data;
  final int byteLength;
  final List<int> shape;
  final int type;
}

final class _OrtGraph {
  _OrtGraph(String path) : _session = createOrtSession(path);

  final OrtSessionObjects _session;
  var _closed = false;

  /// Runs the graph and copies every output as float32.
  ///
  /// Takes ownership of each input's native buffer.
  List<Float32List> run(List<_Input> inputs, List<String> outputNames) {
    final api = _session.api;
    final inputCount = inputs.length;
    final outputCount = outputNames.length;
    final memoryInfo = calloc<Pointer<OrtMemoryInfo>>();
    final values = calloc<Pointer<OrtValue>>(inputCount == 0 ? 1 : inputCount);
    final inputNames = calloc<Pointer<Char>>(inputCount == 0 ? 1 : inputCount);
    final outputs = calloc<Pointer<OrtValue>>(outputCount);
    final nativeOutputNames = calloc<Pointer<Char>>(outputCount);
    final runOptions = calloc<Pointer<OrtRunOptions>>();
    final names = <Pointer<Utf8>>[];
    try {
      if (_closed) throw StateError('ORT graph is closed');
      api.createCpuMemoryInfo(memoryInfo);
      for (var i = 0; i < inputCount; i++) {
        final input = inputs[i];
        final shape = calloc<Int64>(input.shape.length);
        try {
          for (var d = 0; d < input.shape.length; d++) {
            shape[d] = input.shape[d];
          }
          final status = api.createTensorWithDataAsOrtValue(
            values + i,
            memoryInfo: memoryInfo.value,
            inputData: input.data,
            inputDataLengthInBytes: input.byteLength,
            inputShape: shape,
            inputShapeLengthInBytes: input.shape.length,
            onnxTensorElementDataType: input.type,
          );
          if (status.isError) {
            throw Exception(api.consumeErrorMessage(status));
          }
        } finally {
          calloc.free(shape);
        }
        final name = input.name.toNativeUtf8();
        names.add(name);
        inputNames[i] = name.cast();
      }
      for (var i = 0; i < outputCount; i++) {
        final name = outputNames[i].toNativeUtf8();
        names.add(name);
        nativeOutputNames[i] = name.cast();
      }
      api.createRunOptions(runOptions);
      api.run(
        session: _session.sessionPtr.value,
        runOptions: runOptions.value,
        inputNames: inputNames,
        inputValues: values,
        inputCount: inputCount,
        outputNames: nativeOutputNames,
        outputCount: outputCount,
        outputValues: outputs,
      );
      return [for (var i = 0; i < outputCount; i++) _copyFloats(outputs[i])];
    } finally {
      for (var i = 0; i < outputCount; i++) {
        if (outputs[i].address != 0) api.releaseValue(outputs[i]);
      }
      for (var i = 0; i < inputCount; i++) {
        if (values[i].address != 0) api.releaseValue(values[i]);
        calloc.free(inputs[i].data);
      }
      if (runOptions.value.address != 0) {
        api.releaseRunOptions(runOptions.value);
      }
      if (memoryInfo.value.address != 0) {
        api.releaseMemoryInfo(memoryInfo.value);
      }
      for (final name in names) {
        malloc.free(name);
      }
      calloc.free(runOptions);
      calloc.free(nativeOutputNames);
      calloc.free(outputs);
      calloc.free(inputNames);
      calloc.free(values);
      calloc.free(memoryInfo);
    }
  }

  Float32List _copyFloats(Pointer<OrtValue> value) {
    final api = _session.api;
    final data = calloc<Pointer<Void>>();
    final info = calloc<Pointer<OrtTensorTypeAndShapeInfo>>();
    final count = calloc<Size>();
    final type = calloc<UnsignedInt>();
    try {
      api.getTensorTypeAndShape(value, info);
      api.getTensorElementType(info.value, type);
      if (type.value !=
          ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT.value) {
        throw StateError('Expected a float32 FUTO model output');
      }
      api.getTensorShapeElementCount(info.value, count);
      api.getTensorMutableData(value, data);
      return Float32List.fromList(
        data.value.cast<Float>().asTypedList(count.value),
      );
    } finally {
      if (info.value.address != 0) {
        api.releaseTensorTypeAndShapeInfo(info.value);
      }
      calloc.free(type);
      calloc.free(count);
      calloc.free(info);
      calloc.free(data);
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    releaseOrtSessionObjects(_session);
  }
}
