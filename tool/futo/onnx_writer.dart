// Minimal ONNX protobuf writer for the pinned FUTO conversion.
// Field numbers follow onnx/onnx.proto (ONNX 1.20.1). No runtime dependency.
import 'dart:convert';
import 'dart:typed_data';

class Proto {
  final _bytes = BytesBuilder(copy: false);
  void _varint(int value) {
    // Unsigned shift also encodes negative int64 values in ten bytes.
    while (value < 0 || value > 127) {
      _bytes.addByte((value & 127) | 128);
      value = value >>> 7;
    }
    _bytes.addByte(value);
  }

  void integer(int field, int value) {
    _varint(field << 3);
    _varint(value);
  }

  void bytes(int field, List<int> value) {
    _varint((field << 3) | 2);
    _varint(value.length);
    _bytes.add(value);
  }

  void string(int field, String value) => bytes(field, utf8.encode(value));
  void message(int field, Proto value) => bytes(field, value.finish());
  void float(int field, double value) {
    _varint((field << 3) | 5);
    _bytes.add(
      (ByteData(4)..setFloat32(0, value, Endian.little)).buffer.asUint8List(),
    );
  }

  Uint8List finish() => _bytes.toBytes();
}

Proto tensor(String name, List<int> dims, int type, List<int> raw) {
  final p = Proto();
  for (final d in dims) {
    p.integer(1, d);
  }
  return p
    ..integer(2, type)
    ..string(8, name)
    ..bytes(9, raw);
}

Proto valueInfo(String name, List<int> dims, int type) {
  final shape = Proto();
  for (final d in dims) {
    shape.message(1, Proto()..integer(1, d));
  }
  final t = Proto()
    ..integer(1, type)
    ..message(2, shape);
  return Proto()
    ..string(1, name)
    ..message(2, Proto()..message(1, t));
}

Proto attribute(String name, Object value) {
  final p = Proto()..string(1, name);
  if (value is int) {
    p
      ..integer(3, value)
      ..integer(20, 2);
  } else if (value is double) {
    p
      ..float(2, value)
      ..integer(20, 1);
  } else if (value is List<int>) {
    for (final v in value) {
      p.integer(8, v);
    }
    p.integer(20, 7);
  } else {
    throw ArgumentError('Unsupported attribute $name: $value');
  }
  return p;
}

class OnnxGraph {
  OnnxGraph(this.name);
  final String name;
  final nodes = <Proto>[];
  final initializers = <Proto>[];
  final inputs = <Proto>[];
  final outputs = <Proto>[];
  int _next = 0;
  String fresh() => 'tmp_${_next++}';
  String add(
    String op,
    List<String> ins, {
    String? output,
    Map<String, Object> attrs = const {},
  }) {
    final out = output ?? fresh();
    final p = Proto();
    for (final i in ins) {
      p.string(1, i);
    }
    p
      ..string(2, out)
      ..string(3, 'node_${nodes.length}')
      ..string(4, op);
    for (final a in attrs.entries) {
      p.message(5, attribute(a.key, a.value));
    }
    nodes.add(p);
    return out;
  }

  String ints(List<int> values, {List<int>? dims}) {
    final data = ByteData(values.length * 8);
    for (var i = 0; i < values.length; i++) {
      data.setInt64(i * 8, values[i], Endian.little);
    }
    return raw(dims ?? [values.length], 7, data.buffer.asUint8List());
  }

  String scalar(num value, {int type = 1}) {
    if (type == 7) {
      return ints([value.toInt()], dims: []);
    }
    final data = ByteData(4)..setFloat32(0, value.toDouble(), Endian.little);
    return raw([], 1, data.buffer.asUint8List());
  }

  String raw(List<int> dims, int type, List<int> data, {String? name}) {
    final id = name ?? fresh();
    initializers.add(tensor(id, dims, type, data));
    return id;
  }

  Uint8List encode() {
    final graph = Proto();
    for (final n in nodes) {
      graph.message(1, n);
    }
    graph.string(2, name);
    for (final t in initializers) {
      graph.message(5, t);
    }
    for (final i in inputs) {
      graph.message(11, i);
    }
    for (final o in outputs) {
      graph.message(12, o);
    }
    return (Proto()
          ..integer(1, 8)
          ..string(2, 'fonnx-futo-pte-converter')
          ..string(3, '1')
          ..string(
            6,
            'FUTO Swipe weights; FUTO Model Weights License 1.0; visible FUTO Swipe attribution required.',
          )
          ..message(7, graph)
          ..message(8, Proto()..integer(2, 17)))
        .finish();
  }
}
