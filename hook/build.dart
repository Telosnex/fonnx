// Native-assets hook for fonnx (fllama ADR 005).
// Release builds and local source builds run the same callback. Consumer
// builds download all three libraries, including the session finalizer.

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_prebuilt/native_prebuilt.dart';

import 'apple_compatibility.dart';
import 'source_build.dart';

void main(List<String> args) async {
  final lines = <String>[];
  void log(String message) => lines.add('[fonnx] $message');
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final timer = Stopwatch()..start();
    await NativePrebuilt(
      input: fonnxCompatibilityInput(input),
      output: output,
      log: log,
    ).run((source) => buildFromSource(input, output, source, log));
    log('Hook completed in ${timer.elapsedMilliseconds}ms');
  }).whenComplete(() {
    if (lines.isNotEmpty) stderr.write(lines.join('\n'));
  });
}
