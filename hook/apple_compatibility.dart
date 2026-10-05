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
  final os = input.config.code.targetOS;
  final minimum = switch (os) {
    OS.iOS => 15,
    OS.macOS => 14,
    _ => null,
  };
  if (minimum == null) return input;
  final json = jsonDecode(jsonEncode(input.json)) as Map<String, dynamic>;
  final code =
      json['config']['extensions']['code_assets'] as Map<String, dynamic>;
  final apple = code[os.name] as Map<String, dynamic>;
  final version = apple['target_version'] as int;
  if (version >= minimum) return input;
  apple['target_version'] = minimum;
  return BuildInput(json);
}
