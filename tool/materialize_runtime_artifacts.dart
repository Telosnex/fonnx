import 'dart:io';

import 'package:kiln/kiln.dart';
import 'package:path/path.dart' as p;

/// Downloads exactly the files that the consumer hook publishes, for the
/// native smoke scripts.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    throw const FormatException(
      'Usage: dart run tool/materialize_runtime_artifacts.dart <target> <output-directory>',
    );
  }
  final root = File.fromUri(Platform.script).parent.parent;
  final manifest = (await PrebuiltManifest.load(root.uri))!;
  final targetName = arguments[0];
  final target = manifest.targets[targetName];
  if (target == null) throw ArgumentError.value(targetName, 'target');
  final output = Directory(arguments[1]);
  await output.create(recursive: true);
  for (final file in target.files.where((f) => f.delivery == Delivery.bundle)) {
    final cached = await fetchVerified(
      file.fetchSpec,
      File(p.join(defaultCacheRoot().path, file.sha256, file.name)),
      archiveCache: defaultCacheRoot(),
      log: stderr.writeln,
    );
    final published = await cached.copy(p.join(output.path, file.name));
    final apple =
        targetName.startsWith('macos-') || targetName.startsWith('ios-');
    final alias = switch (file.asset) {
      'onnx/ort_ffi_bindings.dart' when apple => 'libonnxruntime.1.dylib',
      'onnx/ort_ffi_bindings.dart' when targetName.startsWith('linux-') =>
        'libonnxruntime.so.1',
      _ => null,
    };
    if (alias != null) {
      final link = Link(p.join(output.path, alias));
      if (await link.exists()) await link.delete();
      await link.create(file.name);
    }
    if (targetName.startsWith('ios-') &&
        file.asset == 'onnx/ort_ffi_bindings.dart') {
      final framework = Directory(p.join(output.path, 'onnxruntime.framework'));
      await framework.create();
      final link = Link(p.join(framework.path, 'onnxruntime'));
      if (await link.exists()) await link.delete();
      await link.create('../${file.name}');
    }
    stdout.writeln(
      '${file.asset}: ${published.path} (${await published.length()} bytes)',
    );
  }
}
