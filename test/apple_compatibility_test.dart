import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks/hooks.dart';

import '../hook/apple_compatibility.dart';

BuildInput inputFor(String os, int version) => BuildInput({
  'out_dir_shared': '${Directory.systemTemp.path}/fonnx_minimum_os_test/',
  'out_file': '${Directory.systemTemp.path}/fonnx_minimum_os_test/output.json',
  'package_name': 'fonnx',
  'package_root': Directory.current.path,
  'config': {
    'build_asset_types': ['code_assets/code'],
    'extensions': {
      'code_assets': {
        'link_mode_preference': 'dynamic',
        'target_architecture': 'arm64',
        'target_os': os,
        if (os == 'ios')
          'ios': {'target_version': version, 'target_sdk': 'iphoneos'},
        if (os == 'macos') 'macos': {'target_version': version},
        if (os == 'android') 'android': {'target_ndk_api': version},
      },
    },
    'linking_enabled': false,
  },
});

void main() {
  test(
    'Flutter iOS 13 uses the declared floor without changing source input',
    () {
      final original = inputFor('ios', 13);
      final effective = fonnxCompatibilityInput(original);
      expect(effective.config.code.iOS.targetVersion, 15);
      expect(original.config.code.iOS.targetVersion, 13);
    },
  );

  test(
    'Flutter macOS 13 uses the declared floor without changing source input',
    () {
      final original = inputFor('macos', 13);
      expect(
        fonnxCompatibilityInput(original).config.code.macOS.targetVersion,
        14,
      );
      expect(original.config.code.macOS.targetVersion, 13);
    },
  );

  test('higher Apple versions stay higher', () {
    for (final os in ['ios', 'macos']) {
      final original = inputFor(os, 20);
      expect(fonnxCompatibilityInput(original), same(original));
    }
  });

  test('non-Apple configurations are unchanged', () {
    for (final os in ['android', 'linux', 'windows']) {
      final original = inputFor(os, 24);
      expect(fonnxCompatibilityInput(original), same(original));
    }
  });
}
