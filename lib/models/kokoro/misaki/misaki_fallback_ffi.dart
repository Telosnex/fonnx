import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:fonnx/models/kokoro/misaki/misaki_en.dart';
import 'package:fonnx/models/kokoro/misaki/misaki_fallback.dart';
import 'package:fonnx/onnx/ort.dart';
import 'package:fonnx/onnx/ort_ffi_bindings.dart' hide calloc, free, malloc;

/// [MisakiFallbackVocab] on the native ORT session.
class MisakiFallbackFfi {
  MisakiFallbackFfi(this.session, String configJson)
    : vocab = MisakiFallbackVocab(configJson);

  final OrtSessionObjects session;
  final MisakiFallbackVocab vocab;

  MisakiPs call(MToken token) {
    final src = vocab.source(token.text);
    if (src == null) return (null, null);
    final dec = <int>[MisakiFallbackVocab.bos];
    while (!vocab.done(dec)) {
      dec.add(_argmaxLast(src, dec));
    }
    return vocab.phonemes(dec);
  }

  int _argmaxLast(List<int> src, List<int> dec) {
    final api = session.api;
    final memoryInfo = calloc<Pointer<OrtMemoryInfo>>();
    final srcValue = calloc<Pointer<OrtValue>>();
    final decValue = calloc<Pointer<OrtValue>>();
    final inputValues = calloc<Pointer<OrtValue>>(2);
    final inputNames = calloc<Pointer<Char>>(2);
    final outputValues = calloc<Pointer<OrtValue>>(1);
    final outputNames = calloc<Pointer<Char>>(1);
    final runOptions = calloc<Pointer<OrtRunOptions>>();
    final srcName = 'input_ids'.toNativeUtf8();
    final decName = 'decoder_input_ids'.toNativeUtf8();
    final logitsName = 'logits'.toNativeUtf8();
    final data = calloc<Pointer<Void>>();
    final shapeInfo = calloc<Pointer<OrtTensorTypeAndShapeInfo>>();
    final count = calloc<Size>();
    Pointer<Int64>? srcData, decData;
    try {
      api.createCpuMemoryInfo(memoryInfo);
      srcData = api.createInt64Tensor(
        srcValue,
        memoryInfo: memoryInfo.value,
        values: src,
        shape: [1, src.length],
      );
      decData = api.createInt64Tensor(
        decValue,
        memoryInfo: memoryInfo.value,
        values: dec,
        shape: [1, dec.length],
      );
      inputNames[0] = srcName.cast<Char>();
      inputNames[1] = decName.cast<Char>();
      inputValues[0] = srcValue.value;
      inputValues[1] = decValue.value;
      outputNames[0] = logitsName.cast<Char>();
      api.createRunOptions(runOptions);
      api.run(
        session: session.sessionPtr.value,
        runOptions: runOptions.value,
        inputNames: inputNames,
        inputValues: inputValues,
        inputCount: 2,
        outputNames: outputNames,
        outputValues: outputValues,
        outputCount: 1,
      );
      api.getTensorMutableData(outputValues[0], data);
      api.getTensorTypeAndShape(outputValues[0], shapeInfo);
      api.getTensorShapeElementCount(shapeInfo.value, count);
      // Logits span the shared 63-token vocabulary, not just phonemes.
      final vocab = count.value ~/ dec.length;
      final logits = data.value.cast<Float>().asTypedList(count.value);
      final o = (dec.length - 1) * vocab;
      var best = 0;
      for (var i = 1; i < vocab; i++) {
        if (logits[o + i] > logits[o + best]) best = i;
      }
      return best;
    } finally {
      if (outputValues[0].address != 0) api.releaseValue(outputValues[0]);
      if (runOptions.value.address != 0) {
        api.releaseRunOptions(runOptions.value);
      }
      if (shapeInfo.value.address != 0) {
        api.releaseTensorTypeAndShapeInfo(shapeInfo.value);
      }
      if (srcValue.value.address != 0) api.releaseValue(srcValue.value);
      if (decValue.value.address != 0) api.releaseValue(decValue.value);
      if (memoryInfo.value.address != 0) {
        api.releaseMemoryInfo(memoryInfo.value);
      }
      if (srcData != null) calloc.free(srcData);
      if (decData != null) calloc.free(decData);
      malloc.free(srcName);
      malloc.free(decName);
      malloc.free(logitsName);
      for (final p in <Pointer>[
        data,
        shapeInfo,
        count,
        runOptions,
        outputNames,
        outputValues,
        inputNames,
        inputValues,
        decValue,
        srcValue,
        memoryInfo,
      ]) {
        calloc.free(p);
      }
    }
  }
}
