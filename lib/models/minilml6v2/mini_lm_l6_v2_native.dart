import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:fonnx/fonnx.dart';
import 'package:fonnx/models/minilml6v2/mini_lm_l6_v2.dart';
import 'package:fonnx/ort_manager.dart';
import 'package:ml_linalg/linalg.dart';

MiniLmL6V2 getMiniLmL6V2(String path) => MiniLmL6V2Native(path);

class MiniLmL6V2Native implements MiniLmL6V2 {
  final String modelPath;
  final OnnxIsolateManager _onnxIsolateManager = OnnxIsolateManager();

  MiniLmL6V2Native(this.modelPath);

  Fonnx? _fonnx;

  @override
  Future<Vector> getEmbeddingAsVector(List<int> tokens) async {
    final embeddings = await getEmbedding(tokens);
    final vector =
        Vector.fromList(embeddings, dtype: DType.float32).normalize();
    return vector;
  }

  Future<Float32List> getEmbedding(
      List<int> tokens) async {
    await _onnxIsolateManager.start();
    if (!kIsWeb && Platform.environment['FLUTTER_TEST'] == 'true') {
      return _onnxIsolateManager.sendInference(modelPath, tokens);
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return getEmbeddingViaPlatformChannel(tokens);
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return getEmbeddingViaFfi(tokens);
      case TargetPlatform.fuchsia:
        throw UnimplementedError();
    }
  }

  Future<Float32List> getEmbeddingViaFfi(List<int> tokens) {
    return _onnxIsolateManager.sendInference(modelPath, tokens);
  }

  Future<Float32List> getEmbeddingViaPlatformChannel(List<int> tokens) async {
    final fonnx = _fonnx ??= Fonnx();
    final embeddings = await fonnx.miniLmL6V2(
      modelPath: modelPath,
      inputs: tokens,
    );
    if (embeddings == null) {
      throw Exception('Embeddings returned from platform code are null');
    }
    return embeddings;
  }

  // Future<Float32List> _getEmbeddingFfi(List<int> tokens) async {
  //   final objects = _session;
  //   final memoryInfo = calloc<Pointer<OrtMemoryInfo>>();
  //   objects.api.createCpuMemoryInfo(memoryInfo);
  //   final inputIdsValue = calloc<Pointer<OrtValue>>();
  //   objects.api.createInt64Tensor(
  //     inputIdsValue,
  //     memoryInfo: memoryInfo.value,
  //     values: tokens,
  //   );
  //   final inputMaskValue = calloc<Pointer<OrtValue>>();
  //   objects.api.createInt64Tensor(
  //     inputMaskValue,
  //     memoryInfo: memoryInfo.value,
  //     values: List.generate(tokens.length, (index) => 1, growable: false),
  //   );
  //   final tokenTypeValue = calloc<Pointer<OrtValue>>();
  //   objects.api.createInt64Tensor(
  //     tokenTypeValue,
  //     memoryInfo: memoryInfo.value,
  //     values: List.generate(tokens.length, (index) => 0, growable: false),
  //   );
  //   final inputNamesPointer = calloc<Pointer<Pointer<Char>>>(3);
  //   inputNamesPointer[0] = 'input_ids'.toNativeUtf8().cast();
  //   inputNamesPointer[1] = 'token_type_ids'.toNativeUtf8().cast();
  //   inputNamesPointer[2] = 'attention_mask'.toNativeUtf8().cast();
  //   final inputNames = inputNamesPointer.cast<Pointer<Char>>();
  //   final inputValues = calloc<Pointer<OrtValue>>(3);
  //   inputValues[0] = inputIdsValue.value;
  //   inputValues[1] = tokenTypeValue.value;
  //   inputValues[2] = inputMaskValue.value;

  //   final outputNamesPointer = calloc<Pointer<Char>>();
  //   outputNamesPointer[0] = 'embeddings'.toNativeUtf8().cast();

  //   final outputValuesPtr = calloc<Pointer<OrtValue>>();
  //   final outputValues = outputValuesPtr.cast<Pointer<OrtValue>>();
  //   final runOptionsPtr = calloc<Pointer<OrtRunOptions>>();
  //   objects.api.createRunOptions(runOptionsPtr);

  //   objects.api.run(
  //     session: objects.sessionPtr.value,
  //     runOptions: runOptionsPtr.value,
  //     inputNames: inputNames,
  //     inputValues: inputValues,
  //     inputCount: 3,
  //     outputNames: outputNamesPointer,
  //     outputCount: 1,
  //     outputValues: outputValues,
  //   );

  //   final outputTensorDataPointer = calloc<Pointer<Void>>();
  //   objects.api
  //       .getTensorMutableData(outputValues.value, outputTensorDataPointer);
  //   final outputTensorDataPtr = outputTensorDataPointer.value;
  //   final floats = outputTensorDataPtr.cast<Float>();

  //   final tensorTypeAndShape = calloc<Pointer<OrtTensorTypeAndShapeInfo>>();
  //   objects.api.getTensorTypeAndShape(outputValues.value, tensorTypeAndShape);
  //   final tensorShapeElementCount = calloc<Size>();
  //   objects.api.getTensorShapeElementCount(
  //     tensorTypeAndShape.value,
  //     tensorShapeElementCount,
  //   );
  //   final elementCount = tensorShapeElementCount.value;
  //   final floatList = floats.asTypedList(elementCount);

  //   calloc.free(memoryInfo);
  //   calloc.free(inputIdsValue);
  //   calloc.free(inputMaskValue);
  //   calloc.free(tokenTypeValue);
  //   calloc.free(inputNamesPointer);
  //   calloc.free(inputValues);
  //   calloc.free(outputNamesPointer);
  //   calloc.free(outputValuesPtr);
  //   calloc.free(runOptionsPtr);
  //   calloc.free(outputTensorDataPointer);
  //   calloc.free(tensorTypeAndShape);
  //   calloc.free(tensorShapeElementCount);

  //   return floatList;
  // }
}
