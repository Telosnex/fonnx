import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:fonnx/onnx/ort.dart';
import 'package:fonnx/onnx/ort_ffi_bindings.dart' hide calloc, free, malloc;

import '../keyword_spotter_types.dart';

final class NativeKwsOnnxBackend implements KwsOnnxBackend {
  NativeKwsOnnxBackend(KeywordSpotterBundle bundle)
    : _encoder = _OrtGraph(bundle.encoderPath, disableKleidiAi: true),
      _decoder = _OrtGraph(bundle.decoderPath),
      _joiner = _OrtGraph(bundle.joinerPath) {
    _resetStates();
  }

  static const _joinerDimension = 320;
  static const _vocabularySize = 500;

  final _OrtGraph _encoder;
  final _OrtGraph _decoder;
  final _OrtGraph _joiner;
  List<_OwnedOrtValue> _states = <_OwnedOrtValue>[];
  var _closed = false;

  @override
  Future<KwsEncoderOutput> runEncoder(Float32List features) async {
    _ensureOpen();
    if (features.length != 45 * 80) {
      throw ArgumentError.value(features.length, 'features.length');
    }
    final input = _encoder.floatTensor(features, const [1, 45, 80]);
    List<Pointer<OrtValue>> outputs = const [];
    try {
      outputs = _encoder.run(
        inputNames: <String>['x', ..._stateInputNames],
        inputValues: <Pointer<OrtValue>>[
          input.value,
          ..._states.map((state) => state.value),
        ],
        outputNames: <String>['encoder_out', ..._stateOutputNames],
      );
      final values = _encoder.copyFloatTensor(outputs.first);
      if (values.length % _joinerDimension != 0) {
        throw StateError('Unexpected encoder output length ${values.length}');
      }

      final oldStates = _states;
      _states = outputs
          .skip(1)
          .map((value) => _OwnedOrtValue(_encoder, value))
          .toList(growable: false);
      _encoder.releaseValue(outputs.first);
      outputs = const [];
      for (final state in oldStates) {
        state.release();
      }
      return KwsEncoderOutput(
        values: values,
        frameCount: values.length ~/ _joinerDimension,
      );
    } finally {
      input.release();
      for (final output in outputs) {
        _encoder.releaseValue(output);
      }
    }
  }

  @override
  Future<Float32List> runDecoder(Int64List tokenContexts) async {
    _ensureOpen();
    if (tokenContexts.length.isOdd) {
      throw ArgumentError.value(tokenContexts.length, 'tokenContexts.length');
    }
    final batch = tokenContexts.length ~/ 2;
    final input = _decoder.int64Tensor(tokenContexts, <int>[batch, 2]);
    final outputs = _decoder.run(
      inputNames: const ['y'],
      inputValues: [input.value],
      outputNames: const ['decoder_out'],
    );
    try {
      final result = _decoder.copyFloatTensor(outputs.single);
      if (result.length != batch * _joinerDimension) {
        throw StateError('Unexpected decoder output length ${result.length}');
      }
      return result;
    } finally {
      input.release();
      for (final output in outputs) {
        _decoder.releaseValue(output);
      }
    }
  }

  @override
  Future<Float32List> runJoiner(
    Float32List encoderVectors,
    Float32List decoderVectors,
  ) async {
    _ensureOpen();
    if (encoderVectors.length != decoderVectors.length ||
        encoderVectors.length % _joinerDimension != 0) {
      throw ArgumentError('Invalid joiner vector dimensions');
    }
    final batch = encoderVectors.length ~/ _joinerDimension;
    final encoderInput = _joiner.floatTensor(encoderVectors, <int>[
      batch,
      _joinerDimension,
    ]);
    final decoderInput = _joiner.floatTensor(decoderVectors, <int>[
      batch,
      _joinerDimension,
    ]);
    final outputs = _joiner.run(
      inputNames: const ['encoder_out', 'decoder_out'],
      inputValues: [encoderInput.value, decoderInput.value],
      outputNames: const ['logit'],
    );
    try {
      final result = _joiner.copyFloatTensor(outputs.single);
      if (result.length != batch * _vocabularySize) {
        throw StateError('Unexpected joiner output length ${result.length}');
      }
      return result;
    } finally {
      encoderInput.release();
      decoderInput.release();
      for (final output in outputs) {
        _joiner.releaseValue(output);
      }
    }
  }

  @override
  Future<void> resetEncoderState() async {
    _ensureOpen();
    _resetStates();
  }

  void _resetStates() {
    for (final state in _states) {
      state.release();
    }
    _states = <_OwnedOrtValue>[];
    for (var layer = 0; layer < 6; layer++) {
      final left = _leftContexts[layer];
      final key = _keyDimensions[layer];
      final value = _valueDimensions[layer];
      final convolution = _convolutionKernels[layer] ~/ 2;
      _states
        ..add(_encoder.zeroFloatTensor(<int>[left, 1, key]))
        ..add(_encoder.zeroFloatTensor(<int>[1, 1, left, 96]))
        ..add(_encoder.zeroFloatTensor(<int>[left, 1, value]))
        ..add(_encoder.zeroFloatTensor(<int>[left, 1, value]))
        ..add(_encoder.zeroFloatTensor(<int>[1, 128, convolution]))
        ..add(_encoder.zeroFloatTensor(<int>[1, 128, convolution]));
    }
    _states
      ..add(_encoder.zeroFloatTensor(const [1, 128, 3, 19]))
      ..add(_encoder.zeroInt64Tensor(const [1]));
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final state in _states) {
      state.release();
    }
    _states = <_OwnedOrtValue>[];
    _encoder.close();
    _decoder.close();
    _joiner.close();
  }

  void _ensureOpen() {
    if (_closed) throw StateError('KWS ONNX backend is closed');
  }
}

const _leftContexts = <int>[64, 32, 16, 8, 16, 32];
const _keyDimensions = <int>[128, 128, 128, 256, 128, 128];
const _valueDimensions = <int>[48, 48, 48, 96, 48, 48];
const _convolutionKernels = <int>[31, 31, 15, 15, 15, 31];

final _stateInputNames = <String>[
  for (var layer = 0; layer < 6; layer++) ...<String>[
    'cached_key_$layer',
    'cached_nonlin_attn_$layer',
    'cached_val1_$layer',
    'cached_val2_$layer',
    'cached_conv1_$layer',
    'cached_conv2_$layer',
  ],
  'embed_states',
  'processed_lens',
];

final _stateOutputNames = <String>[
  for (var layer = 0; layer < 6; layer++) ...<String>[
    'new_cached_key_$layer',
    'new_cached_nonlin_attn_$layer',
    'new_cached_val1_$layer',
    'new_cached_val2_$layer',
    'new_cached_conv1_$layer',
    'new_cached_conv2_$layer',
  ],
  'new_embed_states',
  'new_processed_lens',
];

final class _OrtGraph {
  _OrtGraph(String path, {bool disableKleidiAi = false})
    : _session = createOrtSession(
        path,
        // ORT 1.27.0's Apple SME convolution path mishandles the asymmetric
        // padding in the Zipformer encoder. Remove this after the Native Asset
        // moves to ORT 1.27.1+, which contains microsoft/onnxruntime#28571.
        sessionConfigEntries: disableKleidiAi
            ? const {'mlas.disable_kleidiai': '1'}
            : const {},
      );

  final OrtSessionObjects _session;
  var _closed = false;

  _OwnedOrtValue floatTensor(Float32List values, List<int> shape) {
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

  _OwnedOrtValue zeroFloatTensor(List<int> shape) {
    final count = shape.fold<int>(1, (total, dimension) => total * dimension);
    final data = calloc<Float>(count);
    return _tensor(
      data: data.cast<Void>(),
      byteLength: count * sizeOf<Float>(),
      shape: shape,
      type: ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT.value,
      backing: data.cast<Void>(),
    );
  }

  _OwnedOrtValue int64Tensor(Int64List values, List<int> shape) {
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

  _OwnedOrtValue zeroInt64Tensor(List<int> shape) {
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

  _OwnedOrtValue _tensor({
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
      return _OwnedOrtValue(this, value.value, backing: backing);
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

  Float32List copyFloatTensor(Pointer<OrtValue> value) {
    final data = calloc<Pointer<Void>>();
    final shape = calloc<Pointer<OrtTensorTypeAndShapeInfo>>();
    final count = calloc<Size>();
    try {
      _session.api.getTensorMutableData(value, data);
      _session.api.getTensorTypeAndShape(value, shape);
      _session.api.getTensorShapeElementCount(shape.value, count);
      return Float32List.fromList(
        data.value.cast<Float>().asTypedList(count.value),
      );
    } finally {
      if (shape.value.address != 0) {
        _session.api.releaseTensorTypeAndShapeInfo(shape.value);
      }
      calloc.free(count);
      calloc.free(shape);
      calloc.free(data);
    }
  }

  void releaseValue(Pointer<OrtValue> value) =>
      _session.api.releaseValue(value);

  void close() {
    if (_closed) return;
    _closed = true;
    releaseOrtSessionObjects(_session);
  }
}

final class _OwnedOrtValue {
  _OwnedOrtValue(this.owner, this.value, {this.backing});

  final _OrtGraph owner;
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
