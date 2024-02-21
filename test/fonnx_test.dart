import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fonnx/fonnx_platform_interface.dart';
import 'package:fonnx/fonnx_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockFonnxPlatform
    with MockPlatformInterfaceMixin
    implements FonnxPlatform {
  @override
  Future<String?> getPlatformVersion() => throw UnimplementedError();

  @override
  Future<Float32List> magika({required String modelPath, required List<int> bytes}) {
    throw UnimplementedError();
  }

  @override
  Future<Float32List?> miniLm(
      {required String modelPath, required List<int> inputs}) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>?> sileroVad(
      {required String modelPath,
      required List<int> audioBytes,
      required Map<String, dynamic> previousState}) {
    throw UnimplementedError();
  }

  @override
  Future<String?> whisper(
      {required String modelPath, required List<int> audioBytes}) {
    throw UnimplementedError();
  }
}

void main() {
  final FonnxPlatform initialPlatform = FonnxPlatform.instance;

  test('$MethodChannelFonnx is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelFonnx>());
  });
}
