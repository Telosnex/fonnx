import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:fonnx/models/kokoro/kokoro_vocab.dart';
import 'package:fonnx/onnx/ort.dart';
import 'package:fonnx/onnx/ort_ffi_bindings.dart' hide calloc, free, malloc;

const kokoroSampleRate = 24000;
const kokoroStyleDim = 256;

/// Kokoro's context is 512 tokens including the two pad tokens.
const kokoroMaxPhonemeTokens = 510;

/// Converts a misaki phoneme string to Kokoro token ids, without pads.
///
/// Mirrors the upstream tokenizer.json: characters outside the vocabulary are
/// dropped, every remaining character is one token.
List<int> kokoroPhonemesToIds(String phonemes) {
  final ids = <int>[];
  for (final rune in phonemes.runes) {
    final id = kokoroVocab[String.fromCharCode(rune)];
    if (id != null) ids.add(id);
  }
  if (ids.length > kokoroMaxPhonemeTokens) {
    throw ArgumentError.value(
      ids.length,
      'phonemes',
      'Kokoro accepts at most $kokoroMaxPhonemeTokens phoneme tokens; '
          'split the text into chunks first',
    );
  }
  return ids;
}

/// Selects the style row for an utterance of [tokenCount] phoneme tokens.
///
/// Voice files are float32 arrays shaped [510, 1, 256]; upstream indexes the
/// row by the unpadded phoneme count minus one.
Float32List kokoroStyleForLength(Float32List voice, int tokenCount) {
  final rows = voice.length ~/ kokoroStyleDim;
  if (rows == 0 || voice.length % kokoroStyleDim != 0) {
    throw ArgumentError('Voice data is not a multiple of $kokoroStyleDim');
  }
  if (tokenCount < 1 || tokenCount > kokoroMaxPhonemeTokens) {
    throw ArgumentError.value(tokenCount, 'tokenCount');
  }
  final row = (tokenCount - 1).clamp(0, rows - 1);
  return Float32List.sublistView(
    voice,
    row * kokoroStyleDim,
    (row + 1) * kokoroStyleDim,
  );
}

/// Runs Kokoro on unpadded phoneme [ids]. Returns 24 kHz float PCM.
Float32List runKokoroFfi(
  OrtSessionObjects session, {
  required List<int> ids,
  required Float32List voice,
  double speed = 1.0,
}) {
  final style = kokoroStyleForLength(voice, ids.length);
  final paddedIds = <int>[0, ...ids, 0];

  final api = session.api;
  final memoryInfo = calloc<Pointer<OrtMemoryInfo>>();
  final idsValue = calloc<Pointer<OrtValue>>();
  final styleValue = calloc<Pointer<OrtValue>>();
  final speedValue = calloc<Pointer<OrtValue>>();
  final inputValues = calloc<Pointer<OrtValue>>(3);
  final inputNames = calloc<Pointer<Char>>(3);
  final outputValues = calloc<Pointer<OrtValue>>(1);
  final outputNames = calloc<Pointer<Char>>(1);
  final runOptions = calloc<Pointer<OrtRunOptions>>();

  final idsName = 'input_ids'.toNativeUtf8();
  final styleName = 'style'.toNativeUtf8();
  final speedName = 'speed'.toNativeUtf8();
  final waveformName = 'waveform'.toNativeUtf8();

  Pointer<Int64>? idsData;
  Pointer<Float>? styleData;
  Pointer<Float>? speedData;

  try {
    api.createCpuMemoryInfo(memoryInfo);
    idsData = api.createInt64Tensor(
      idsValue,
      memoryInfo: memoryInfo.value,
      values: paddedIds,
      shape: <int>[1, paddedIds.length],
    );
    styleData = api.createFloat32Tensor2D(
      styleValue,
      memoryInfo: memoryInfo.value,
      values: <List<double>>[style],
    );
    speedData = api.createFloat32Tensor(
      speedValue,
      memoryInfo: memoryInfo.value,
      values: <double>[speed],
    );

    inputNames[0] = idsName.cast<Char>();
    inputNames[1] = styleName.cast<Char>();
    inputNames[2] = speedName.cast<Char>();
    inputValues[0] = idsValue.value;
    inputValues[1] = styleValue.value;
    inputValues[2] = speedValue.value;
    outputNames[0] = waveformName.cast<Char>();

    api.createRunOptions(runOptions);
    api.run(
      session: session.sessionPtr.value,
      runOptions: runOptions.value,
      inputNames: inputNames,
      inputValues: inputValues,
      inputCount: 3,
      outputNames: outputNames,
      outputValues: outputValues,
      outputCount: 1,
    );
    return _readFloats(api, outputValues[0]);
  } finally {
    if (outputValues[0].address != 0) api.releaseValue(outputValues[0]);
    if (runOptions.value.address != 0) {
      api.releaseRunOptions(runOptions.value);
    }
    for (final value in <Pointer<Pointer<OrtValue>>>[
      idsValue,
      styleValue,
      speedValue,
    ]) {
      if (value.value.address != 0) api.releaseValue(value.value);
    }
    if (memoryInfo.value.address != 0) {
      api.releaseMemoryInfo(memoryInfo.value);
    }
    if (idsData != null) calloc.free(idsData);
    if (styleData != null) calloc.free(styleData);
    if (speedData != null) calloc.free(speedData);
    malloc.free(idsName);
    malloc.free(styleName);
    malloc.free(speedName);
    malloc.free(waveformName);
    calloc.free(runOptions);
    calloc.free(outputNames);
    calloc.free(outputValues);
    calloc.free(inputNames);
    calloc.free(inputValues);
    calloc.free(speedValue);
    calloc.free(styleValue);
    calloc.free(idsValue);
    calloc.free(memoryInfo);
  }
}

Float32List _readFloats(OrtApi api, Pointer<OrtValue> value) {
  final data = calloc<Pointer<Void>>();
  final shape = calloc<Pointer<OrtTensorTypeAndShapeInfo>>();
  final count = calloc<Size>();
  try {
    api.getTensorMutableData(value, data);
    api.getTensorTypeAndShape(value, shape);
    api.getTensorShapeElementCount(shape.value, count);
    return Float32List.fromList(
      data.value.cast<Float>().asTypedList(count.value),
    );
  } finally {
    if (shape.value.address != 0) {
      api.releaseTensorTypeAndShapeInfo(shape.value);
    }
    calloc.free(count);
    calloc.free(shape);
    calloc.free(data);
  }
}

/// Encodes mono float PCM as a 16-bit WAV file.
Uint8List kokoroWav(Float32List samples, {int sampleRate = kokoroSampleRate}) {
  final dataBytes = samples.length * 2;
  final out = ByteData(44 + dataBytes);
  void ascii(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      out.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  out.setUint32(4, 36 + dataBytes, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  out.setUint32(16, 16, Endian.little);
  out.setUint16(20, 1, Endian.little);
  out.setUint16(22, 1, Endian.little);
  out.setUint32(24, sampleRate, Endian.little);
  out.setUint32(28, sampleRate * 2, Endian.little);
  out.setUint16(32, 2, Endian.little);
  out.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  out.setUint32(40, dataBytes, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    final s = (samples[i].clamp(-1.0, 1.0) * 32767).round();
    out.setInt16(44 + i * 2, s, Endian.little);
  }
  return out.buffer.asUint8List();
}
