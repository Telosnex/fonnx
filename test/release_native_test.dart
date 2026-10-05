import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_prebuilt/native_prebuilt.dart';
import 'package:native_prebuilt/src/publisher.dart';

import '../hook/upstream_ort.dart';
import '../tool/release_native.dart';

final class RecordingPublisher implements Publisher {
  List<File>? uploaded;
  @override
  Future<void> publish({
    required String repository,
    required String tag,
    required List<File> assets,
    required String notes,
  }) async => uploaded = assets;
  @override
  Future<Map<String, String>?> publishedAssetDigests({
    required String repository,
    required String tag,
  }) async => null;
}

void main() {
  test(
    'release keeps upstream ORT URL and uploads only compiled files',
    () async {
      final work = await Directory.systemTemp.createTemp('fonnx_release_test_');
      addTearDown(() => work.delete(recursive: true));
      final package = Directory('${work.path}/package');
      final artifacts = Directory('${work.path}/artifacts');
      await Directory(
        '${package.path}/native_artifacts',
      ).create(recursive: true);
      await artifacts.create();
      await File('${package.path}/pubspec.yaml').writeAsString('name: fonnx\n');
      final files = [
        ('libonnxruntime.dylib', ortAsset, 'ORT upstream bytes'),
        ('libortextensions.dylib', extensionsAsset, 'Extensions bytes'),
        (
          'libfonnx_ort_session_finalizer.dylib',
          finalizerAsset,
          'finalizer bytes',
        ),
      ];
      final hashes = <String, String>{};
      for (final (name, _, bytes) in files) {
        await File('${artifacts.path}/$name').writeAsString(bytes);
        hashes[name] = sha256.convert(utf8.encode(bytes)).toString();
      }
      const upstreamUrl = 'https://example.com/onnxruntime-macos-arm64.tgz';
      await File(
        '${package.path}/native_artifacts/upstream_ort.json',
      ).writeAsString(
        jsonEncode({
          'schema': 1,
          'version': '1.27.0',
          'targets': {
            'macos-arm64': {
              'url': upstreamUrl,
              'sha256': hashes[files.first.$1],
              'downloadSha256': 'a' * 64,
              'archiveEntry': 'upstream/lib/libonnxruntime.dylib',
            },
          },
        }),
      );
      final key = (await computeSourceKey(package.uri)).key;
      await File('${artifacts.path}/target.json').writeAsString(
        jsonEncode({
          'schema': 1,
          'package': 'fonnx',
          'target': 'macos-arm64',
          'sourceKey': key,
          'runner': 'test',
          'toolchain': 'test',
          'minOSVersion': 14,
          'files': [
            for (final (name, asset, _) in files)
              {
                'name': name,
                'asset': asset,
                'sha256': hashes[name],
                'delivery': 'bundle',
              },
          ],
        }),
      );
      final publisher = RecordingPublisher();
      final released = await releaseNative(
        packageRoot: package.uri,
        directories: [artifacts],
        repository: 'Telosnex/fonnx',
        staging: Directory('${work.path}/staging'),
        publisher: publisher,
      );
      final target = released.targets['macos-arm64']!;
      expect(target.files, hasLength(3));
      expect(target.minOSVersion, 14);
      expect(
        target.files.singleWhere((f) => f.asset == ortAsset).url,
        upstreamUrl,
      );
      expect(
        target.files.singleWhere((f) => f.asset == ortAsset).archiveEntry,
        'upstream/lib/libonnxruntime.dylib',
      );
      expect(publisher.uploaded, hasLength(2));
      expect(
        publisher.uploaded!.every((f) => !f.path.contains('-libonnxruntime.')),
        isTrue,
      );
      expect((await PrebuiltManifest.load(package.uri))!.sourceKey, key);
    },
  );
}
