import 'dart:convert';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

/// FONNX requires iOS 15.1 and macOS 14, including source builds. Flutter
/// 3.47 reports 13 to every Apple hook instead of the app's deployment target
/// (flutter/flutter#145104). Building from source cannot lower ORT's minimum.
///
/// Use FONNX's declared floor for prebuilt selection. Keep the original input
/// for source builds and output validation. The manifest records the real
/// minimum (iOS major 15, with 15.1 in the package profile), not Flutter's 13.
/// Apps must still configure their deployment targets and the iOS framework
/// packaging fix described in README.md. Remove this adapter when Flutter
/// passes the app's real minimum to hooks.
BuildInput fonnxCompatibilityInput(BuildInput input) {
  final code = input.config.code;
  final (minimum, current) = switch (code.targetOS) {
    OS.iOS => (AppleVersion(15), code.iOS.deploymentVersion),
    OS.macOS => (AppleVersion(14), code.macOS.deploymentVersion),
    _ => (null, null),
  };
  if (minimum == null || current == null || current >= minimum) return input;
  final json = jsonDecode(jsonEncode(input.json)) as Map<String, dynamic>;
  final extension =
      json['config']['extensions']['code_assets'] as Map<String, dynamic>;
  final apple = extension[code.targetOS.name] as Map<String, dynamic>;
  // Both keys: deployment_version (code_assets 2.2) and target_version.
  apple['target_version'] = minimum.major;
  apple['deployment_version'] = {
    'major': minimum.major,
    'minor': minimum.minor,
    'patch': minimum.patch,
  };
  return BuildInput(json);
}
