import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:fonnx/onnx/ort_ffi_bindings.dart' hide calloc, free, malloc;
import 'package:fonnx/src/ort_session_graph.dart';

import '../whisper.dart';
import 'whisper_engine.dart';
import 'whisper_features.dart';

/// Runs Whisper's encoder and merged decoder with ORT through FFI.
final class NativeWhisperOnnxBackend implements WhisperOnnxBackend {
  NativeWhisperOnnxBackend(this._bundle)
    : _encoder = OrtSessionGraph(_bundle.encoderPath),
      _decoder = OrtSessionGraph(_bundle.decoderPath) {
    final layers = _bundle.decoderLayers;
    _pastNames = [
      for (var i = 0; i < layers; i++) ...[
        'past_key_values.$i.decoder.key',
        'past_key_values.$i.decoder.value',
      ],
      for (var i = 0; i < layers; i++) ...[
        'past_key_values.$i.encoder.key',
        'past_key_values.$i.encoder.value',
      ],
    ];
    _presentNames = [
      for (final name in _pastNames)
        name.replaceFirst('past_key_values', 'present'),
    ];
  }

  static const _encoderFrames = 1500;
  static const _headDimension = 64;

  final WhisperBundle _bundle;
  final OrtSessionGraph _encoder;
  final OrtSessionGraph _decoder;

  /// Decoder self-attention caches first, then encoder cross-attention.
  late final List<String> _pastNames;
  late final List<String> _presentNames;

  OwnedOrtValue? _hiddenStates;
  var _selfCache = <OwnedOrtValue>[];
  var _crossCache = <OwnedOrtValue>[];
  var _batch = 0;
  var _cachedPositions = 0;
  var _closed = false;

  int get _selfCount => 2 * _bundle.decoderLayers;

  @override
  Future<void> encode(Float32List features, int batch) async {
    _ensureOpen();
    if (features.length != whisperMelBins * whisperFrames) {
      throw ArgumentError.value(features.length, 'features.length');
    }
    _releaseState();
    final input = _encoder.floatTensor(features, const [
      1,
      whisperMelBins,
      whisperFrames,
    ]);
    List<Pointer<OrtValue>> outputs = const [];
    try {
      outputs = _encoder.run(
        inputNames: const ['input_features'],
        inputValues: [input.value],
        outputNames: const ['last_hidden_state'],
      );
      final hidden = _encoder.floatData(outputs.single);
      final width = hidden.length ~/ _encoderFrames;
      if (width != _bundle.attentionHeads * _headDimension) {
        throw StateError(
          'Whisper encoder width $width does not match ${_bundle.attentionHeads} '
          'attention heads',
        );
      }
      // Every row starts from the same audio.
      final count = batch * hidden.length;
      final buffer = calloc<Float>(count);
      final view = buffer.asTypedList(count);
      for (var row = 0; row < batch; row++) {
        view.setAll(row * hidden.length, hidden);
      }
      _hiddenStates = _decoder.adoptFloatBuffer(buffer, count, [
        batch,
        _encoderFrames,
        width,
      ]);
      _batch = batch;
    } finally {
      input.release();
      for (final output in outputs) {
        _encoder.releaseValue(output);
      }
    }
  }

  @override
  Future<Float32List> decode(
    Int32List tokens,
    int length,
    Int32List? parents,
  ) async {
    _ensureOpen();
    final hiddenStates = _hiddenStates;
    if (hiddenStates == null) throw StateError('Call encode first');
    if (tokens.length != _batch * length) {
      throw ArgumentError.value(tokens.length, 'tokens.length');
    }
    final first = _cachedPositions == 0;
    if (!first && parents != null) _reorder(parents);

    final ids = _decoder.int64Tensor(Int64List.fromList(tokens), [
      _batch,
      length,
    ]);
    final useCache = _decoder.boolTensor([!first], const [1]);
    final emptyPast = first
        ? [
            for (var i = 0; i < _pastNames.length; i++)
              _decoder.zeroFloatTensor([
                _batch,
                _bundle.attentionHeads,
                0,
                _headDimension,
              ]),
          ]
        : const <OwnedOrtValue>[];
    final past = first ? emptyPast : [..._selfCache, ..._crossCache];
    // After the first step the cross-attention cache does not change, so
    // only the self-attention cache is fetched.
    final outputNames = [
      'logits',
      ...(first ? _presentNames : _presentNames.take(_selfCount)),
    ];
    List<Pointer<OrtValue>> outputs = const [];
    try {
      outputs = _decoder.run(
        inputNames: [
          'input_ids',
          'encoder_hidden_states',
          'use_cache_branch',
          ..._pastNames,
        ],
        inputValues: [
          ids.value,
          hiddenStates.value,
          useCache.value,
          for (final value in past) value.value,
        ],
        outputNames: outputNames,
      );

      final logits = _decoder.floatData(outputs.first);
      if (logits.length != _batch * length * whisperVocabularySize) {
        throw StateError('Unexpected Whisper logits length ${logits.length}');
      }
      final last = Float32List(_batch * whisperVocabularySize);
      for (var row = 0; row < _batch; row++) {
        final start = (row * length + length - 1) * whisperVocabularySize;
        last.setRange(
          row * whisperVocabularySize,
          (row + 1) * whisperVocabularySize,
          logits,
          start,
        );
      }

      final positions = _cachedPositions + length;
      final presentSelf = _decoder.floatData(outputs[1]);
      if (presentSelf.length !=
          _batch * _bundle.attentionHeads * positions * _headDimension) {
        throw StateError(
          'Whisper decoder cache does not match ${_bundle.decoderLayers} '
          'layers and ${_bundle.attentionHeads} heads',
        );
      }
      for (final value in _selfCache) {
        value.release();
      }
      _selfCache = [
        for (var i = 0; i < _selfCount; i++)
          OwnedOrtValue(_decoder, outputs[1 + i]),
      ];
      if (first) {
        _crossCache = [
          for (var i = _selfCount; i < _presentNames.length; i++)
            OwnedOrtValue(_decoder, outputs[1 + i]),
        ];
      }
      _decoder.releaseValue(outputs.first);
      outputs = const [];
      _cachedPositions = positions;
      return last;
    } finally {
      ids.release();
      useCache.release();
      for (final value in emptyPast) {
        value.release();
      }
      for (final output in outputs) {
        _decoder.releaseValue(output);
      }
    }
  }

  /// Makes cache row i a copy of the old row [parents]\[i].
  void _reorder(Int32List parents) {
    if (parents.length != _batch) {
      throw ArgumentError.value(parents.length, 'parents.length');
    }
    var identity = true;
    for (var i = 0; i < parents.length; i++) {
      if (parents[i] != i) identity = false;
    }
    if (identity) return;
    final shape = [
      _batch,
      _bundle.attentionHeads,
      _cachedPositions,
      _headDimension,
    ];
    _selfCache = [
      for (final old in _selfCache) _gatherRows(old, parents, shape),
    ];
  }

  OwnedOrtValue _gatherRows(
    OwnedOrtValue old,
    Int32List parents,
    List<int> shape,
  ) {
    final data = _decoder.floatData(old.value);
    final rowLength = data.length ~/ _batch;
    final buffer = calloc<Float>(data.length);
    final view = buffer.asTypedList(data.length);
    for (var row = 0; row < _batch; row++) {
      view.setRange(
        row * rowLength,
        (row + 1) * rowLength,
        data,
        parents[row] * rowLength,
      );
    }
    final value = _decoder.adoptFloatBuffer(buffer, data.length, shape);
    old.release();
    return value;
  }

  void _releaseState() {
    _hiddenStates?.release();
    _hiddenStates = null;
    for (final value in [..._selfCache, ..._crossCache]) {
      value.release();
    }
    _selfCache = [];
    _crossCache = [];
    _batch = 0;
    _cachedPositions = 0;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _releaseState();
    _encoder.close();
    _decoder.close();
  }

  void _ensureOpen() {
    if (_closed) throw StateError('Whisper ONNX backend is closed');
  }
}
