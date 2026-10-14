import 'dart:ffi';
import 'dart:typed_data';

import 'package:fonnx/onnx/ort_ffi_bindings.dart' hide calloc, free, malloc;
import 'package:fonnx/src/ort_session_graph.dart';

import '../nemo_asr.dart';
import 'nemo_asr_engine.dart';

/// Runs a NeMo model's graphs with ORT through FFI.
final class NativeNemoAsrOnnxBackend implements NemoAsrOnnxBackend {
  NativeNemoAsrOnnxBackend(NemoAsrBundle bundle)
    : _model = bundle.model,
      _graphs = _open(bundle.paths);

  /// Opens one session per path. A failure closes the ones already open.
  static List<OrtSessionGraph> _open(List<String> paths) {
    final graphs = <OrtSessionGraph>[];
    try {
      for (final path in paths) {
        graphs.add(OrtSessionGraph(path));
      }
      return graphs;
    } catch (_) {
      for (final graph in graphs) {
        graph.close();
      }
      rethrow;
    }
  }

  /// Parakeet TDT v3: encoder width, prediction network layers and width.
  static const _encoderWidth = 1024;
  static const _predictionLayers = 2;
  static const _predictionWidth = 640;

  final NemoAsrModel _model;
  final List<OrtSessionGraph> _graphs;

  /// TDT: the encoder output, frames × width.
  Float32List? _encoded;
  OwnedOrtValue? _prediction;
  var _state = <OwnedOrtValue>[];
  var _closed = false;

  OrtSessionGraph get _encoder => _graphs[0];
  OrtSessionGraph get _decoder => _graphs[1];
  OrtSessionGraph get _joiner => _graphs[2];

  @override
  Future<Float32List> encode(Float32List features, int frames) async {
    _ensureOpen();
    _releaseState();
    final bins = features.length ~/ frames;
    final input = _encoder.floatTensor(features, [1, bins, frames]);
    final length = _encoder.int64Tensor(Int64List.fromList([frames]), [1]);
    final ctc = _model == NemoAsrModel.fastConformerCtcMultilingual;
    List<Pointer<OrtValue>> outputs = const [];
    try {
      outputs = _encoder.run(
        inputNames: const ['audio_signal', 'length'],
        inputValues: [input.value, length.value],
        outputNames: ctc ? const ['logprobs'] : const ['outputs'],
      );
      if (ctc) return _encoder.copyFloatTensor(outputs.single);
      // outputs is 1 × width × frames. The joiner reads one frame at a time.
      final data = _encoder.floatData(outputs.single);
      final encodedFrames = data.length ~/ _encoderWidth;
      final encoded = Float32List(data.length);
      for (var c = 0; c < _encoderWidth; c++) {
        for (var t = 0; t < encodedFrames; t++) {
          encoded[t * _encoderWidth + c] = data[c * encodedFrames + t];
        }
      }
      _encoded = encoded;
      _state = [
        for (var i = 0; i < 2; i++)
          _decoder.zeroFloatTensor(const [
            _predictionLayers,
            1,
            _predictionWidth,
          ]),
      ];
      await predict(parakeetTdtV3Blank);
      return Float32List.fromList([encodedFrames.toDouble()]);
    } finally {
      input.release();
      length.release();
      for (final output in outputs) {
        _encoder.releaseValue(output);
      }
    }
  }

  @override
  Future<Float32List> joint(int frame) async {
    _ensureOpen();
    final encoded = _encoded;
    final prediction = _prediction;
    if (encoded == null || prediction == null) {
      throw StateError('Call encode first');
    }
    final input = _joiner.floatTensor(
      Float32List.sublistView(
        encoded,
        frame * _encoderWidth,
        (frame + 1) * _encoderWidth,
      ),
      const [1, _encoderWidth, 1],
    );
    List<Pointer<OrtValue>> outputs = const [];
    try {
      outputs = _joiner.run(
        inputNames: const ['encoder_outputs', 'decoder_outputs'],
        inputValues: [input.value, prediction.value],
        outputNames: const ['outputs'],
      );
      return _joiner.copyFloatTensor(outputs.single);
    } finally {
      input.release();
      for (final output in outputs) {
        _joiner.releaseValue(output);
      }
    }
  }

  @override
  Future<void> predict(int token) async {
    _ensureOpen();
    if (_state.length != 2) throw StateError('Call encode first');
    final targets = _decoder.int32Tensor(Int32List.fromList([token]), const [
      1,
      1,
    ]);
    final length = _decoder.int32Tensor(Int32List.fromList([1]), const [1]);
    List<Pointer<OrtValue>> outputs = const [];
    try {
      // The input and output names are those of the sherpa-onnx export: the
      // LSTM's hidden state, then its cell state.
      outputs = _decoder.run(
        inputNames: const [
          'targets',
          'target_length',
          'states.1',
          'onnx::Slice_3',
        ],
        inputValues: [
          targets.value,
          length.value,
          _state[0].value,
          _state[1].value,
        ],
        outputNames: const ['outputs', 'states', '162'],
      );
      _prediction?.release();
      for (final value in _state) {
        value.release();
      }
      _prediction = OwnedOrtValue(_decoder, outputs[0]);
      _state = [
        OwnedOrtValue(_decoder, outputs[1]),
        OwnedOrtValue(_decoder, outputs[2]),
      ];
      outputs = const [];
    } finally {
      targets.release();
      length.release();
      for (final output in outputs) {
        _decoder.releaseValue(output);
      }
    }
  }

  void _releaseState() {
    _encoded = null;
    _prediction?.release();
    _prediction = null;
    for (final value in _state) {
      value.release();
    }
    _state = [];
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _releaseState();
    for (final graph in _graphs) {
      graph.close();
    }
  }

  void _ensureOpen() {
    if (_closed) throw StateError('NemoAsr ONNX backend is closed');
  }
}
