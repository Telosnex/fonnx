// Convert the three ADR 011 FUTO ExecuTorch programs to core ONNX opset 17.
// Usage: dart run tool/futo/convert.dart <output-dir> <flatc-executable>
// Requires flatc 25.2.10. Downloads SHA-256-pinned models and BSD schemas.
// No GPL swipe-library source or training checkpoint is used.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'onnx_writer.dart';
import 'sources.dart';
import 'bundle.dart';

Map<String, dynamic> map(dynamic x) => (x as Map).cast<String, dynamic>();
List<int> ints(dynamic x) => (x as List).cast<int>();
int type(dynamic t) => switch (t) {
  'FLOAT' => 1,
  'LONG' => 7,
  'BOOL' => 9,
  _ => throw StateError('Unsupported dtype $t'),
};
int elements(List<int> shape) => shape.fold(1, (a, b) => a * b);

Future<Uint8List> download(HttpClient client, String url, String hash) async {
  final response = await (await client.getUrl(Uri.parse(url))).close();
  if (response.statusCode != 200) {
    throw HttpException('$url: ${response.statusCode}');
  }
  final b = await response.fold<BytesBuilder>(
    BytesBuilder(copy: false),
    (b, c) => b..add(c),
  );
  final bytes = b.takeBytes();
  if (sha256.convert(bytes).toString() != hash) {
    throw StateError('Hash mismatch: $url');
  }
  return bytes;
}

class Pte {
  Pte(this.bytes, this.program);
  final Uint8List bytes;
  final Map<String, dynamic> program;
  late final base = ByteData.sublistView(bytes).getUint64(24, Endian.little);
  Uint8List segment(int index) {
    final s = map(program['segments'][index]);
    final start = base + (s['offset'] as int);
    return Uint8List.sublistView(bytes, start, start + (s['size'] as int));
  }

  Uint8List constant(int index, int length) {
    final s = map(program['constant_segment']);
    final b = segment(s['segment_index']);
    final offset = s['offsets'][index] as int;
    return Uint8List.sublistView(b, offset, offset + length);
  }

  Uint8List named(String key) {
    final entry = (program['named_data'] as List).singleWhere(
      (e) => e['key'] == key,
    );
    return segment(entry['segment_index']);
  }
}

Future<Map<String, dynamic>> decompile(
  String flatc,
  File binary,
  String schema,
  Directory work,
) async {
  final result = await Process.run(flatc, [
    '--json',
    '--strict-json',
    '--defaults-json',
    '-o',
    work.path,
    schema,
    '--',
    binary.path,
  ]);
  if (result.exitCode != 0) {
    throw StateError('flatc: ${result.stderr}');
  }
  final stem = binary.uri.pathSegments.last.replaceFirst(
    RegExp(r'\.[^.]+$'),
    '',
  );
  final text = File('${work.path}/$stem.json')
      .readAsStringSync()
      .replaceAllMapped(
        RegExp(r'(?<![\w"])(-?inf|nan)(?![\w"])'),
        (m) => '"${m[0]}"',
      );
  final decoded = map(jsonDecode(text));
  if (schema.endsWith('/schema.fbs')) {
    restoreXnnBounds(binary.readAsBytesSync(), decoded);
  }
  return decoded;
}

void restoreXnnBounds(Uint8List bytes, Map<String, dynamic> decoded) {
  // flatc JSON rounds float fields to six decimals (1e-7 becomes 0).
  // Read activation bounds from their exact IEEE-754 flatbuffer bytes.
  final data = ByteData.sublistView(bytes);
  int field(int table, int index) {
    final vt = table - data.getInt32(table, Endian.little);
    final entry = 4 + index * 2;
    if (entry >= data.getUint16(vt, Endian.little)) {
      return 0;
    }
    final offset = data.getUint16(vt + entry, Endian.little);
    return offset == 0 ? 0 : table + offset;
  }

  int pointer(int location) =>
      location + data.getUint32(location, Endian.little);
  final root = data.getUint32(0, Endian.little);
  final vector = pointer(field(root, 1));
  final nodes = decoded['xnodes'] as List;
  if (data.getUint32(vector, Endian.little) != nodes.length) {
    throw StateError('XNN node count mismatch');
  }
  for (var i = 0; i < nodes.length; i++) {
    final node = pointer(vector + 4 + i * 4);
    final location = field(node, 3);
    if (location != 0) {
      final bounds = pointer(location);
      double read(int index) {
        final f = field(bounds, index);
        return f == 0 ? 0 : data.getFloat32(f, Endian.little);
      }

      nodes[i]['output_min_max'] = {
        'output_min': read(0),
        'output_max': read(1),
      };
    }
  }
}

class Converter {
  Converter(this.pte, this.plan, this.graph);
  final Pte pte;
  final Map<String, dynamic> plan;
  final OnnxGraph graph;
  late final values = (plan['values'] as List).map((e) => map(e)).toList();
  Map<String, dynamic> val(int i) => map(values[i]['val']);
  dynamic literal(int i) {
    final v = val(i);
    return switch (values[i]['val_type']) {
      'Null' => null,
      'Int' => v['int_val'],
      'Double' => v['double_val'],
      'Bool' => v['bool_val'],
      'IntList' => [for (final j in ints(v['items'])) literal(j) as int],
      _ => throw StateError('Not a literal: ${values[i]}'),
    };
  }

  List<int> shape(int i) => ints(val(i)['sizes']);
  String e(int i) => 'e$i';
  final produced = <int>[];
  void mark(int i) {
    produced.remove(i);
    produced.add(i);
  }

  void ensure(int i) {
    if (produced.contains(i)) {
      return;
    }
    final v = val(i), alloc = v['allocation_info'];
    if (values[i]['val_type'] != 'Tensor' || alloc == null) {
      throw StateError('Undefined tensor $i');
    }
    final aliases = produced.reversed.where((j) {
      final other = val(j)['allocation_info'];
      return other != null &&
          jsonEncode(other) == jsonEncode(alloc) &&
          elements(shape(j)) == elements(shape(i));
    });
    if (aliases.isEmpty) {
      throw StateError('No producer for view $i');
    }
    reshape(e(aliases.first), shape(i), output: e(i));
    mark(i);
  }

  String scalarArg(int i, {int tensorType = 1}) {
    final v = literal(i);
    final n = v is num
        ? v
        : v == '-inf'
        ? double.negativeInfinity
        : v == 'inf'
        ? double.infinity
        : double.parse(v as String);
    return graph.scalar(n, type: tensorType);
  }

  String reshape(String input, List<int> dims, {String? output}) =>
      graph.add('Reshape', [input, graph.ints(dims)], output: output);
  String transpose(String input, List<int> perm, {String? output}) =>
      graph.add('Transpose', [input], output: output, attrs: {'perm': perm});
  String clip(String input, double min, double max, {String? output}) =>
      graph.add('Clip', [
        input,
        graph.scalar(min),
        graph.scalar(max),
      ], output: output);
  void initialize() {
    for (var i = 0; i < values.length; i++) {
      if (values[i]['val_type'] != 'Tensor') {
        continue;
      }
      final v = val(i);
      final dims = shape(i);
      final t = type(v['scalar_type']);
      if (ints(v['dim_order']).asMap().entries.any((x) => x.key != x.value) ||
          v['storage_offset'] != 0 ||
          v['shape_dynamism'] != 'STATIC') {
        throw StateError('Unsupported tensor layout $i');
      }
      if (v['data_buffer_idx'] != 0) {
        mark(i);
        graph.raw(
          dims,
          t,
          pte.constant(
            v['data_buffer_idx'],
            elements(dims) *
                (t == 7
                    ? 8
                    : t == 9
                    ? 1
                    : 4),
          ),
          name: e(i),
        );
      }
    }
    final names = interfaceNames;
    for (final (position, i) in ints(plan['inputs']).indexed) {
      mark(i);
      final name = names.$1[position];
      graph.inputs.add(valueInfo(name, shape(i), type(val(i)['scalar_type'])));
      graph.add('Identity', [name], output: e(i));
    }
    for (final (position, i) in ints(plan['outputs']).indexed) {
      graph.outputs.add(
        valueInfo(names.$2[position], shape(i), type(val(i)['scalar_type'])),
      );
    }
  }

  (List<String>, List<String>) get interfaceNames => switch (graph.name) {
    'honorable_sturgeon_forward' => (
      ['features', 'layout_keys', 'layout_mask'],
      ['log_emissions', 'coefficients', 'intention'],
    ),
    'magic_macaw_forward' => (['features'], ['log_emissions']),
    'hungry_jellyfish_forward' => (
      ['token_ids', 'hash_buckets'],
      ['context_states'],
    ),
    'hungry_jellyfish_get_embeddings' => (
      <String>[],
      [
        'exact_embeddings',
        'exact_biases',
        'hashed_embeddings',
        'hashed_biases',
      ],
    ),
    _ => throw StateError('Unknown FUTO method ${graph.name}'),
  };
  void finish() {
    for (final (position, i) in ints(plan['outputs']).indexed) {
      ensure(i);
      graph.add('Identity', [e(i)], output: interfaceNames.$2[position]);
    }
  }

  void kernel(Map<String, dynamic> call) {
    final op = plan['operators'][call['op_index']]['name'] as String;
    final a = ints(call['args']);
    final written = op == 'aten::native_layer_norm'
        ? [a[5], a[6], a[7]]
        : op == 'aten::split_with_sizes_copy'
        ? ints(val(a[3])['items'])
        : [a[a.length - 2]];
    final reads = op == 'aten::arange' || op == 'aten::scalar_tensor'
        ? <int>[]
        : op == 'aten::native_layer_norm'
        ? [a[0], a[2], a[3]]
        : op == 'aten::where'
        ? [a[0], if (values[a[1]]['val_type'] == 'Tensor') a[1], a[2]]
        : op == 'aten::atan2' || op == 'aten::embedding'
        ? [a[0], a[1]]
        : [a[0]];
    for (final i in reads) {
      ensure(i);
    }
    final output = e(a[a.length - 2]);
    switch (op) {
      case 'aten::arange':
        final dims = shape(a[3]);
        final start = literal(a[0]) as int;
        final step = literal(a[2]) as int;
        final data = ByteData(elements(dims) * 4);
        for (var i = 0; i < elements(dims); i++) {
          data.setFloat32(i * 4, (start + i * step).toDouble(), Endian.little);
        }
        graph.raw(dims, 1, data.buffer.asUint8List(), name: e(a[3]));
      case 'aten::scalar_tensor':
        final s = scalarArg(a[0]);
        graph.add('Identity', [s], output: e(a[1]));
      case 'dim_order_ops::_to_dim_order_copy':
        graph.add(
          'Cast',
          [e(a[0])],
          output: output,
          attrs: {'to': type(val(a[a.length - 2])['scalar_type'])},
        );
      case 'aten::select_copy':
        graph.add(
          'Gather',
          [e(a[0]), graph.scalar(literal(a[2]) as int, type: 7)],
          output: output,
          attrs: {'axis': literal(a[1]) as int},
        );
      case 'aten::unsqueeze_copy':
        graph.add('Unsqueeze', [
          e(a[0]),
          graph.ints([literal(a[1]) as int]),
        ], output: output);
      case 'aten::squeeze_copy':
        graph.add('Squeeze', [
          e(a[0]),
          graph.ints(ints(literal(a[1]))),
        ], output: output);
      case 'aten::expand_copy':
        graph.add('Expand', [e(a[0]), graph.ints(shape(a[3]))], output: output);
      case 'aten::bitwise_not':
        graph.add('Not', [e(a[0])], output: output);
      case 'aten::atan2':
        final y = e(a[0]), x = e(a[1]);
        final zero = graph.scalar(0), pi = graph.scalar(math.pi);
        final angle = graph.add('Atan', [
          graph.add('Div', [y, x]),
        ]);
        final negY = graph.add('Less', [y, zero]);
        final adjusted = graph.add('Where', [
          negY,
          graph.add('Sub', [angle, pi]),
          graph.add('Add', [angle, pi]),
        ]);
        final nonzero = graph.add('Where', [
          graph.add('Less', [x, zero]),
          adjusted,
          angle,
        ]);
        final yzero = graph.add('Equal', [y, zero]);
        final half = graph.scalar(math.pi / 2);
        final vertical = graph.add('Where', [
          yzero,
          zero,
          graph.add('Where', [negY, graph.scalar(-math.pi / 2), half]),
        ]);
        graph.add('Where', [
          graph.add('Equal', [x, zero]),
          vertical,
          nonzero,
        ], output: output);
      case 'aten::full_like':
        final s = scalarArg(a[1]);
        graph.add('Expand', [s, graph.ints(shape(a[3]))], output: output);
      case 'aten::gt':
      case 'aten::lt':
        final t = type(val(a[0])['scalar_type']);
        graph.add(op == 'aten::gt' ? 'Greater' : 'Less', [
          e(a[0]),
          scalarArg(a[1], tensorType: t),
        ], output: output);
      case 'aten::where':
        final a1 = values[a[1]]['val_type'] == 'Tensor'
            ? e(a[1])
            : scalarArg(a[1]);
        graph.add('Where', [e(a[0]), a1, e(a[2])], output: output);
      case 'aten::cumsum':
        graph.add('CumSum', [
          e(a[0]),
          graph.scalar(literal(a[1]) as int, type: 7),
        ], output: output);
      case 'aten::split_with_sizes_copy':
        final sizes = ints(literal(a[1])), axis = literal(a[2]) as int;
        final outs = ints(val(a[3])['items']);
        var start = 0;
        for (var i = 0; i < outs.length; i++) {
          graph.add('Slice', [
            e(a[0]),
            graph.ints([start]),
            graph.ints([start + sizes[i]]),
            graph.ints([axis]),
          ], output: e(outs[i]));
          start += sizes[i];
        }
      case 'aten::_log_softmax':
        graph.add(
          'LogSoftmax',
          [e(a[0])],
          output: output,
          attrs: {'axis': literal(a[1]) as int},
        );
      case 'aten::clamp':
        final t = type(val(a[0])['scalar_type']);
        graph.add('Min', [
          e(a[0]),
          scalarArg(a[2], tensorType: t),
        ], output: output);
        if (literal(a[1]) != null) {
          throw StateError('Unexpected clamp minimum');
        }
      case 'aten::embedding':
        graph.add(
          'Gather',
          [e(a[0]), e(a[1])],
          output: output,
          attrs: {'axis': 0},
        );
      case 'aten::sum':
        graph.add(
          'ReduceSum',
          [e(a[0]), graph.ints(ints(literal(a[1])))],
          output: output,
          attrs: {'keepdims': literal(a[2]) == true ? 1 : 0},
        );
      case 'aten::native_layer_norm':
        final x = e(a[0]);
        final axes = [shape(a[0]).length - 1];
        final mean = graph.add(
          'ReduceMean',
          [x],
          output: e(a[6]),
          attrs: {'axes': axes, 'keepdims': 1},
        );
        final centered = graph.add('Sub', [x, mean]);
        final variance = graph.add(
          'ReduceMean',
          [
            graph.add('Mul', [centered, centered]),
          ],
          attrs: {'axes': axes, 'keepdims': 1},
        );
        final std = graph.add('Sqrt', [
          graph.add('Add', [variance, scalarArg(a[4])]),
        ]);
        final inverse = graph.add('Div', [
          graph.scalar(1),
          std,
        ], output: e(a[7]));
        graph.add('Add', [
          graph.add('Mul', [
            graph.add('Mul', [centered, inverse]),
            e(a[2]),
          ]),
          e(a[3]),
        ], output: e(a[5]));
      default:
        throw StateError('Unsupported kernel $op');
    }
    for (final i in written) {
      mark(i);
    }
  }

  void delegate(Map<String, dynamic> call, Map<String, dynamic> g, int serial) {
    final a = ints(call['args']);
    final vs = {
      for (final v in g['xvalues'] as List)
        v['xvalue_union']['id_out'] as int: map(v['xvalue_union']),
    };
    String x(int i) => 'd${serial}x$i';
    for (final id in ints(g['input_ids'])) {
      final v = vs[id]!;
      final idx = a[v['external_id'] as int];
      ensure(idx);
      reshape(e(idx), ints(v['dims']), output: x(id));
    }
    for (final entry in vs.entries) {
      final v = entry.value;
      if (v['datatype'] != 'xnn_datatype_fp32') {
        throw StateError('Non-FP32 XNN tensor');
      }
      final ci = v['constant_buffer_idx'] as int;
      if (ci != 0) {
        final c = map(g['constant_data'][ci]);
        final bytes = pte.named(c['named_key']);
        final dims = ints(v['dims']);
        final count = elements(dims) * 4;
        if (count != c['size'] || bytes.length < count) {
          throw StateError('Constant shape mismatch');
        }
        graph.raw(
          dims,
          1,
          Uint8List.sublistView(bytes, 0, count),
          name: x(entry.key),
        );
      }
    }
    const binary = {
      'XNNAdd': 'Add',
      'XNNSubtract': 'Sub',
      'XNNMultiply': 'Mul',
      'XNNDiv': 'Div',
      'XNNBatchMatrixMultiply': 'MatMul',
    };
    const unary = {
      'XNNSquareRoot': 'Sqrt',
      'XNNCos': 'Cos',
      'XNNLog': 'Log',
      'XNNHardswish': 'HardSwish',
    };
    for (final node in g['xnodes'] as List) {
      final n = map(node['xnode_union']);
      final op = node['xnode_union_type'] as String;
      final out = x(n['output_id']);
      final bounds = node['output_min_max'];
      final target = bounds == null ? out : graph.fresh();
      final flags = n['flags'] as int;
      if (flags != 0 && !(op == 'XNNGlobalAvgPooling2d' && flags == 64)) {
        throw StateError('Unsupported XNN flags $flags');
      }
      if (binary.containsKey(op)) {
        graph.add(binary[op]!, [
          x(n['input1_id']),
          x(n['input2_id']),
        ], output: target);
      } else if (unary.containsKey(op)) {
        graph.add(unary[op]!, [x(n['input_id'])], output: target);
      } else if (op.startsWith('XNNConcatenate')) {
        final count = int.parse(op.substring('XNNConcatenate'.length));
        graph.add(
          'Concat',
          [for (var j = 1; j <= count; j++) x(n['input${j}_id'])],
          output: target,
          attrs: {'axis': n['axis'] as int},
        );
      } else {
        switch (op) {
          case 'XNNStaticReshape':
            reshape(x(n['input_id']), ints(n['new_shape']), output: target);
          case 'XNNStaticTranspose':
            transpose(x(n['input_id']), ints(n['perm']), output: target);
          case 'XNNStaticSlice':
            final starts = ints(n['offsets']), sizes = ints(n['sizes']);
            graph.add('Slice', [
              x(n['input_id']),
              graph.ints(starts),
              graph.ints([
                for (var j = 0; j < sizes.length; j++) starts[j] + sizes[j],
              ]),
            ], output: target);
          case 'XNNSigmoid':
            // ORT's tanh-based Sigmoid rounds small negative logits to zero.
            // XNNPACK preserves exp(x), which feeds Log in the encoder.
            final input = x(n['input_id']);
            final exponential = graph.add('Exp', [
              graph.add('Neg', [
                graph.add('Abs', [input]),
              ]),
            ]);
            final denominator = graph.add('Add', [
              graph.scalar(1),
              exponential,
            ]);
            graph.add('Where', [
              graph.add('Less', [input, graph.scalar(0)]),
              graph.add('Div', [exponential, denominator]),
              graph.add('Div', [graph.scalar(1), denominator]),
            ], output: target);
          case 'XNNSquare':
            graph.add('Mul', [
              x(n['input_id']),
              x(n['input_id']),
            ], output: target);
          case 'XNNClamp':
            graph.add('Identity', [x(n['input_id'])], output: target);
          case 'XNNGlobalAvgPooling2d':
            graph.add(
              'ReduceMean',
              [x(n['input_id'])],
              output: target,
              attrs: {
                'axes': [1, 2],
                'keepdims': 1,
              },
            );
          case 'XNNFullyConnected':
            final w = transpose(x(n['filter_id']), [1, 0]);
            final product = graph.add('MatMul', [x(n['input1_id']), w]);
            if (n['bias_id'] == 4294967295) {
              graph.add('Identity', [product], output: target);
            } else {
              graph.add('Add', [product, x(n['bias_id'])], output: target);
            }
          case 'XNNConv2d':
          case 'XNNDepthwiseConv2d':
            final input = transpose(x(n['input1_id']), [0, 3, 1, 2]);
            final weight = transpose(
              x(n['filter_id']),
              op == 'XNNDepthwiseConv2d' ? [3, 0, 1, 2] : [0, 3, 1, 2],
            );
            final conv = graph.add(
              'Conv',
              [input, weight, if (n['bias_id'] != 4294967295) x(n['bias_id'])],
              attrs: {
                'pads': [
                  n['padding_top'] as int,
                  n['padding_left'] as int,
                  n['padding_bottom'] as int,
                  n['padding_right'] as int,
                ],
                'strides': [
                  n['subsampling_height'] as int,
                  n['subsampling_width'] as int,
                ],
                'dilations': [
                  n['dilation_height'] as int,
                  n['dilation_width'] as int,
                ],
                'group': n['groups'] as int,
              },
            );
            transpose(conv, [0, 2, 3, 1], output: target);
          case 'XNNStaticConstantPad':
            graph.add('Pad', [
              x(n['input_id']),
              graph.ints([
                ...ints(n['pre_paddings']),
                ...ints(n['post_paddings']),
              ]),
              graph.scalar(n['padding_value'] as num),
            ], output: target);
          default:
            throw StateError('Unsupported XNN op $op');
        }
      }
      if (bounds != null) {
        double limit(dynamic v) => v is num
            ? v.toDouble()
            : v == 'inf'
            ? double.infinity
            : v == '-inf'
            ? double.negativeInfinity
            : throw StateError('Invalid clamp bound');
        clip(
          target,
          limit(bounds['output_min']),
          limit(bounds['output_max']),
          output: out,
        );
      }
    }
    for (final id in ints(g['output_ids'])) {
      final v = vs[id]!;
      final idx = a[v['external_id'] as int];
      reshape(x(id), shape(idx), output: e(idx));
      mark(idx);
    }
  }
}

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    throw ArgumentError(
      'Expected output directory and flatc 25.2.10 executable',
    );
  }
  final flatc = File(args[1]).absolute.path;
  final version = await Process.run(flatc, ['--version']);
  if (version.exitCode != 0 || !'${version.stdout}'.contains('25.2.10')) {
    throw StateError('Requires flatc 25.2.10');
  }
  final output = Directory(args[0]).absolute;
  if (output.existsSync() && output.listSync().isNotEmpty) {
    throw ArgumentError('Output directory must be empty');
  }
  final work = Directory.systemTemp.createTempSync('fonnx-futo-export-');
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  final receipt = <String, dynamic>{
    'modelRevision': revision,
    'executorchSchemaRevision': etRevision,
    'converterVersion': 2,
    'opset': 17,
    'irVersion': 8,
    'sources': <String, dynamic>{},
    'outputs': <String, dynamic>{},
    'files': <String, dynamic>{},
    'notice':
        'Derived from FUTO Swipe. Subject to FUTO Model Weights License 1.0 (LICENSE-FUTO.txt). Format conversion only; no training or intentional weight changes. Products must display visible FUTO Swipe attribution.',
  };
  output.createSync(recursive: true);
  try {
    for (final entry in schemas.entries) {
      final b = await download(
        client,
        'https://raw.githubusercontent.com/pytorch/executorch/$etRevision/${entry.key}',
        entry.value,
      );
      File('${work.path}/${entry.key.split('/').last}').writeAsBytesSync(b);
    }
    final modelBytes = <String, Uint8List>{};
    for (final entry in sourceHashes.entries) {
      final url = sourceUrl(entry.key);
      final b = await download(client, url, entry.value);
      (receipt['sources'] as Map)[entry.key] = {
        'url': url,
        'sha256': entry.value,
        'bytes': b.length,
      };
      if (entry.key.endsWith('.pte')) {
        modelBytes[entry.key] = b;
      } else {
        final path = distributedSourcePath(entry.key);
        final f = File('${output.path}/$path')
          ..parent.createSync(recursive: true);
        f.writeAsBytesSync(b);
        (receipt['files'] as Map)[path] = {
          'sha256': entry.value,
          'bytes': b.length,
        };
      }
    }
    for (final entry in modelBytes.entries) {
      final bytes = entry.value;
      if (ascii.decode(bytes.sublist(4, 8)) != 'ET12' ||
          ascii.decode(bytes.sublist(8, 12)) != 'eh00') {
        throw StateError('Unsupported PTE header');
      }
      final name = entry.key.split('/').first;
      final programSize = ByteData.sublistView(
        bytes,
      ).getUint64(16, Endian.little);
      final file = File('${work.path}/$name.pte')
        ..writeAsBytesSync(bytes.sublist(0, programSize));
      final pte = Pte(
        bytes,
        await decompile(flatc, file, '${work.path}/program.fbs', work),
      );
      for (final planValue in pte.program['execution_plan'] as List) {
        final plan = map(planValue);
        final method = plan['name'] as String;
        final converter = Converter(pte, plan, OnnxGraph('${name}_$method'))
          ..initialize();
        final chains = plan['chains'] as List;
        if (chains.length != 1) {
          throw StateError('Unsupported execution chains');
        }
        var serial = 0;
        for (final instruction in chains.single['instructions'] as List) {
          final call = map(instruction['instr_args']);
          if (instruction['instr_args_type'] == 'KernelCall') {
            converter.kernel(call);
          } else if (instruction['instr_args_type'] == 'DelegateCall') {
            final delegate = plan['delegates'][call['delegate_index']];
            if (delegate['id'] != 'XnnpackBackend' ||
                delegate['processed']['location'] != 'SEGMENT') {
              throw StateError('Unsupported delegate');
            }
            final data = pte.segment(delegate['processed']['index']);
            if (ascii.decode(data.sublist(4, 8)) != 'XH00') {
              throw StateError('Unsupported XNN header');
            }
            final header = ByteData.sublistView(data),
                offset = header.getUint32(10, Endian.little),
                size = header.getUint32(14, Endian.little);
            final fb = File('${work.path}/delegate.fb')
              ..writeAsBytesSync(data.sublist(offset, offset + size));
            converter.delegate(
              call,
              await decompile(flatc, fb, '${work.path}/schema.fbs', work),
              serial++,
            );
          } else {
            throw StateError('Unsupported instruction');
          }
        }
        converter.finish();
        final result = converter.graph.encode();
        final path =
            '$name/${method == 'forward'
                ? name == 'hungry_jellyfish'
                      ? 'context_lm'
                      : 'model_fp32'
                : method}.onnx';
        File('${output.path}/$path')
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(result);
        (receipt['outputs'] as Map)[path] = {
          'sha256': sha256.convert(result).toString(),
          'bytes': result.length,
          'inputs': [
            for (final (p, i) in ints(plan['inputs']).indexed)
              {
                'name': converter.interfaceNames.$1[p],
                'shape': converter.shape(i),
                'onnxType': type(converter.val(i)['scalar_type']),
              },
          ],
          'outputs': [
            for (final (p, i) in ints(plan['outputs']).indexed)
              {
                'name': converter.interfaceNames.$2[p],
                'shape': converter.shape(i),
                'onnxType': type(converter.val(i)['scalar_type']),
              },
          ],
        };
        stdout.writeln('$path: ${result.length} bytes');
      }
    }
    final notice = utf8.encode(futoSwipeNotice);
    File('${output.path}/NOTICE.txt').writeAsBytesSync(notice);
    (receipt['files'] as Map)['NOTICE.txt'] = {
      'sha256': sha256.convert(notice).toString(),
      'bytes': notice.length,
    };
    File(
      '${output.path}/manifest.json',
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(receipt));
    await verifyFutoSwipeBundle(output);
  } finally {
    client.close(force: true);
    work.deleteSync(recursive: true);
  }
}
