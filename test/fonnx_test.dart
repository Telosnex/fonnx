import 'package:flutter_test/flutter_test.dart';
import 'package:fonnx/fonnx.dart';
import 'package:fonnx/fonnx_platform_interface.dart';
import 'package:fonnx/fonnx_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockFonnxPlatform
    with MockPlatformInterfaceMixin
    implements FonnxPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final FonnxPlatform initialPlatform = FonnxPlatform.instance;

  test('$MethodChannelFonnx is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelFonnx>());
  });

  test('getPlatformVersion', () async {
    Fonnx fonnxPlugin = Fonnx();
    MockFonnxPlatform fakePlatform = MockFonnxPlatform();
    FonnxPlatform.instance = fakePlatform;

    expect(await fonnxPlugin.getPlatformVersion(), '42');
  });
}
