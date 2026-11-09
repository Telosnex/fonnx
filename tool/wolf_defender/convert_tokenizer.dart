// Converts the tokenizer.json of Patronus Wolf Defender Edge to the compact
// file that WolfDefenderTokenizer reads (lib/models/wolfDefender/src/
// wolf_defender_tokenizer.dart has the format).
//
// Usage: dart run tool/wolf_defender/convert_tokenizer.dart \
//   <tokenizer.json> <wolf_defender_edge_tokenizer.bin>
//
// The tool accepts only the configuration that the Dart tokenizer implements:
// BPE with byte fallback and fused unknowns, a Metaspace pre-tokenizer that
// always prepends, a normalizer that replaces " " with "▁", and added tokens
// that match the original text. Any other configuration fails.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:fonnx/models/wolfDefender/src/wolf_defender_tokenizer.dart';

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln(
      'Usage: dart run tool/wolf_defender/convert_tokenizer.dart '
      '<tokenizer.json> <output.bin>',
    );
    exit(64);
  }
  final source = File(args[0]).readAsBytesSync();
  final json = jsonDecode(utf8.decode(source)) as Map<String, Object?>;
  final bytes = convertTokenizerJson(json);
  File(args[1]).writeAsBytesSync(bytes);
  // Proves that the Dart reader accepts the file.
  WolfDefenderTokenizer.fromBytes(bytes);
  stdout.writeln('source  ${sha256.convert(source)} ${source.length} bytes');
  stdout.writeln('output  ${sha256.convert(bytes)} ${bytes.length} bytes');
}

Uint8List convertTokenizerJson(Map<String, Object?> json) {
  void require(bool condition, String message) {
    if (!condition) throw FormatException('Unsupported tokenizer: $message');
  }

  final model = json['model']! as Map<String, Object?>;
  require(model['type'] == 'BPE', 'model is not BPE');
  require(model['byte_fallback'] == true, 'no byte fallback');
  require(model['fuse_unk'] == true, 'unknowns are not fused');
  require(model['ignore_merges'] == false, 'ignore_merges');
  require(model['dropout'] == null, 'dropout');
  require(model['continuing_subword_prefix'] == null, 'subword prefix');
  require(model['end_of_word_suffix'] == null, 'end-of-word suffix');
  require(model['unk_token'] == '<unk>', 'unknown token');
  require(
    jsonEncode(json['normalizer']) ==
        jsonEncode({
          'type': 'Replace',
          'pattern': {'String': ' '},
          'content': metaspace,
        }),
    'normalizer',
  );
  require(
    jsonEncode(json['pre_tokenizer']) ==
        jsonEncode({
          'type': 'Metaspace',
          'replacement': metaspace,
          'prepend_scheme': 'always',
          'split': true,
        }),
    'pre-tokenizer',
  );

  final vocab = (model['vocab']! as Map<String, Object?>).cast<String, int>();
  final tokens = List<String?>.filled(vocab.length, null);
  for (final MapEntry(:key, :value) in vocab.entries) {
    require(value >= 0 && value < tokens.length, 'IDs are not 0..n-1');
    require(tokens[value] == null, 'duplicate ID $value');
    tokens[value] = key;
  }

  final merges = <(int, int)>[];
  for (final merge in model['merges']! as List<Object?>) {
    final (left, right) = switch (merge) {
      [final String l, final String r] => (l, r),
      final String s when s.split(' ').length == 2 => (
        s.split(' ')[0],
        s.split(' ')[1],
      ),
      _ => throw FormatException('Unsupported merge $merge'),
    };
    final l = vocab[left], r = vocab[right];
    require(l != null && r != null, 'merge $left $right has no IDs');
    require(
      vocab.containsKey(left + right),
      'merge $left $right has no result',
    );
    merges.add((l!, r!));
  }

  final added = <int>[];
  for (final token in json['added_tokens']! as List<Object?>) {
    final t = token! as Map<String, Object?>;
    require(
      t['normalized'] == false &&
          t['lstrip'] == false &&
          t['rstrip'] == false &&
          t['single_word'] == false,
      'added token ${t['content']} has options',
    );
    require(vocab[t['content']] == t['id'], 'added token ${t['content']}');
    added.add(t['id']! as int);
  }

  final out = BytesBuilder(copy: false);
  final header = ByteData(8)
    ..setUint32(0, wolfDefenderTokenizerMagic, Endian.little)
    ..setUint32(4, wolfDefenderTokenizerVersion, Endian.little);
  out.add(header.buffer.asUint8List());
  void u32(int value) => out.add(
    (ByteData(4)..setUint32(0, value, Endian.little)).buffer.asUint8List(),
  );
  u32(tokens.length);
  for (final token in tokens) {
    final utf = utf8.encode(token!);
    require(utf.length < 65536, 'token too long');
    out.add(
      (ByteData(
        2,
      )..setUint16(0, utf.length, Endian.little)).buffer.asUint8List(),
    );
    out.add(utf);
  }
  u32(merges.length);
  for (final (l, r) in merges) {
    u32(l);
    u32(r);
  }
  u32(added.length);
  for (final id in added) {
    u32(id);
  }
  return out.takeBytes();
}
