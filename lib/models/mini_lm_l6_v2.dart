import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:fonnx/onnx/ort.dart';
import 'package:fonnx/onnx/ort_ffi_bindings.dart' hide calloc, free;
import 'package:fonnx/tokenizers/wordpiece_tokenizer.dart';

class MiniLmL6V2 {
  String modelPath;
  MiniLmL6V2(this.modelPath);
  OrtSessionObjects? _sessionObjects;

  Future<OrtSessionObjects> get sessionObjects async {
    _sessionObjects ??= createOrtSession(modelPath);
    return _sessionObjects!;
  }

  Future<Float32List> getEmbedding(String text) async {
    final objects = await sessionObjects;
    final memoryInfo = calloc<Pointer<OrtMemoryInfo>>();
    objects.api.createCpuMemoryInfo(memoryInfo);
    final inputIdsValue = calloc<Pointer<OrtValue>>();
    final tokens = WordpieceTokenizer.bert().tokenize(text);
    objects.api.createInt64Tensor(
      inputIdsValue,
      memoryInfo: memoryInfo.value,
      values: tokens,
    );
    final inputMaskValue = calloc<Pointer<OrtValue>>();
    objects.api.createInt64Tensor(
      inputMaskValue,
      memoryInfo: memoryInfo.value,
      values: List.generate(tokens.length, (index) => 1, growable: false),
    );
    final tokenTypeValue = calloc<Pointer<OrtValue>>();
    objects.api.createInt64Tensor(
      tokenTypeValue,
      memoryInfo: memoryInfo.value,
      values: List.generate(tokens.length, (index) => 0, growable: false),
    );
    final inputNamesPointer = calloc<Pointer<Pointer<Char>>>(3);
    inputNamesPointer[0] = 'input_ids'.toNativeUtf8().cast();
    inputNamesPointer[1] = 'token_type_ids'.toNativeUtf8().cast();
    inputNamesPointer[2] = 'attention_mask'.toNativeUtf8().cast();
    final inputNames = inputNamesPointer.cast<Pointer<Char>>();
    final inputValues = calloc<Pointer<OrtValue>>(3);
    inputValues[0] = inputIdsValue.value;
    inputValues[1] = tokenTypeValue.value;
    inputValues[2] = inputMaskValue.value;

    final outputNamesPointer = calloc<Pointer<Char>>();
    outputNamesPointer[0] = 'embeddings'.toNativeUtf8().cast();

    final outputValuesPtr = calloc<Pointer<OrtValue>>();
    final outputValues = outputValuesPtr.cast<Pointer<OrtValue>>();
    final runOptionsPtr = calloc<Pointer<OrtRunOptions>>();
    objects.api.createRunOptions(runOptionsPtr);

    objects.api.run(
      session: objects.sessionPtr.value,
      runOptions: runOptionsPtr.value,
      inputNames: inputNames,
      inputValues: inputValues,
      inputCount: 3,
      outputNames: outputNamesPointer,
      outputCount: 1,
      outputValues: outputValues,
    );

    final outputTensorDataPointer = calloc<Pointer<Void>>();
    objects.api
        .getTensorMutableData(outputValues.value, outputTensorDataPointer);
    final outputTensorDataPtr = outputTensorDataPointer.value;
    final floats = outputTensorDataPtr.cast<Float>();

    final tensorTypeAndShape = calloc<Pointer<OrtTensorTypeAndShapeInfo>>();
    objects.api.getTensorTypeAndShape(outputValues.value, tensorTypeAndShape);
    final tensorShapeElementCount = calloc<Size>();
    objects.api.getTensorShapeElementCount(
      tensorTypeAndShape.value,
      tensorShapeElementCount,
    );
    final elementCount = tensorShapeElementCount.value;
    final floatList = floats.asTypedList(elementCount);

    calloc.free(memoryInfo);
    calloc.free(inputIdsValue);
    calloc.free(inputMaskValue);
    calloc.free(tokenTypeValue);
    calloc.free(inputNamesPointer);
    calloc.free(inputValues);
    calloc.free(outputNamesPointer);
    calloc.free(outputValuesPtr);
    calloc.free(runOptionsPtr);
    calloc.free(outputTensorDataPointer);
    calloc.free(tensorTypeAndShape);
    calloc.free(tensorShapeElementCount);

    return floatList;
  }
}
