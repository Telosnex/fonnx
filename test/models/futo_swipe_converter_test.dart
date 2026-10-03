import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import '../../tool/futo/convert.dart' as converter;
import '../../tool/futo/onnx_writer.dart';

void main() {
  test(
    'protobuf writes negative int64 attributes without signed-shift loops',
    () {
      final encoded = (Proto()..integer(3, -1)).finish();
      expect(encoded, [24, ...List.filled(9, 255), 1]);
    },
  );
  test('XNN bounds recover exact tiny floats discarded by flatc JSON', () {
    final data = ByteData(112)
      ..setUint32(0, 32, Endian.little)
      ..setUint16(16, 8, Endian.little)
      ..setUint16(22, 4, Endian.little)
      ..setInt32(32, 16, Endian.little)
      ..setUint32(36, 12, Endian.little)
      ..setUint32(48, 1, Endian.little)
      ..setUint32(52, 28, Endian.little)
      ..setUint16(64, 12, Endian.little)
      ..setUint16(74, 4, Endian.little)
      ..setInt32(80, 16, Endian.little)
      ..setUint32(84, 16, Endian.little)
      ..setUint16(88, 8, Endian.little)
      ..setUint16(92, 4, Endian.little)
      ..setUint16(94, 8, Endian.little)
      ..setInt32(100, 12, Endian.little)
      ..setFloat32(104, 1e-7, Endian.little)
      ..setFloat32(108, double.infinity, Endian.little);
    final graph = <String, dynamic>{
      'xnodes': [
        {
          'output_min_max': {'output_min': 0.0, 'output_max': 'inf'},
        },
      ],
    };
    converter.restoreXnnBounds(data.buffer.asUint8List(), graph);
    expect(
      graph['xnodes'][0]['output_min_max']['output_min'],
      data.getFloat32(104, Endian.little),
    );
    expect(graph['xnodes'][0]['output_min_max']['output_max'], double.infinity);
  });
  test('XNN bounds reject a mismatched decoded node count', () {
    final data = ByteData(56)
      ..setUint32(0, 32, Endian.little)
      ..setUint16(16, 8, Endian.little)
      ..setUint16(22, 4, Endian.little)
      ..setInt32(32, 16, Endian.little)
      ..setUint32(36, 12, Endian.little)
      ..setUint32(48, 1, Endian.little);
    expect(
      () =>
          converter.restoreXnnBounds(data.buffer.asUint8List(), {'xnodes': []}),
      throwsStateError,
    );
  });
}
