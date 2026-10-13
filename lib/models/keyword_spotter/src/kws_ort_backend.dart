import 'dart:ffi';
import 'dart:typed_data';

import 'package:fonnx/onnx/ort_ffi_bindings.dart' hide calloc, free, malloc;
import 'package:fonnx/src/ort_session_graph.dart';

import '../keyword_spotter_types.dart';

final class NativeKwsOnnxBackend implements KwsOnnxBackend {
  NativeKwsOnnxBackend(KeywordSpotterBundle bundle)
    : _encoder = OrtSessionGraph(
        bundle.encoderPath,
        // ORT 1.27.0's Apple SME convolution path mishandles the asymmetric
        // padding in the Zipformer encoder. Remove this after the Native Asset
        // moves to ORT 1.27.1+, which contains microsoft/onnxruntime#28571.
        sessionConfigEntries: const {'mlas.disable_kleidiai': '1'},
      ),
      _decoder = OrtSessionGraph(bundle.decoderPath),
      _joiner = OrtSessionGraph(bundle.joinerPath) {
    _resetStates();
  }

  static const _joinerDimension = 320;
  static const _vocabularySize = 500;

  final OrtSessionGraph _encoder;
  final OrtSessionGraph _decoder;
  final OrtSessionGraph _joiner;
  List<OwnedOrtValue> _states = <OwnedOrtValue>[];
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
          .map((value) => OwnedOrtValue(_encoder, value))
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
  Future<Float32List> runDecoder(Int32List tokenContexts) async {
    _ensureOpen();
    if (tokenContexts.length.isOdd) {
      throw ArgumentError.value(tokenContexts.length, 'tokenContexts.length');
    }
    final batch = tokenContexts.length ~/ 2;
    final input = _decoder.int64Tensor(Int64List.fromList(tokenContexts), <int>[
      batch,
      2,
    ]);
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
    _states = <OwnedOrtValue>[];
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
    _states = <OwnedOrtValue>[];
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
