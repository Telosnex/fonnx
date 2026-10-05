import 'dart:convert';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:native_prebuilt/native_prebuilt.dart';

const ortAsset = 'onnx/ort_ffi_bindings.dart';
const extensionsAsset = 'onnx/ort_extensions.dart';
const finalizerAsset = 'onnx/ort_session_finalizer.dart';

/// Microsoft's ORT files, plus the pinned dynamic iOS base. These URLs remain
/// upstream inputs in both source builds and the published prebuilt manifest.
Future<Map<String, PrebuiltFile>> loadUpstreamOrt(Uri packageRoot) async {
  final json =
      jsonDecode(
            await File.fromUri(
              packageRoot.resolve('native_artifacts/upstream_ort.json'),
            ).readAsString(),
          )
          as Map<String, dynamic>;
  if (json['schema'] != 1 || json['version'] != '1.27.0') {
    throw const FormatException('Unsupported upstream ORT pins');
  }
  return {
    for (final entry in (json['targets'] as Map<String, dynamic>).entries)
      entry.key: PrebuiltFile.fromJson({
        ...entry.value as Map<String, dynamic>,
        'name': TargetName.parse(entry.key).os.dylibFileName('onnxruntime'),
        'delivery': 'bundle',
        'asset': ortAsset,
      }, entry.key),
  };
}
