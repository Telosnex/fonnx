// Native-assets hook for fonnx (kiln ADR 001). For a web build it
// installs the web runtime files instead (ADR 002).
// Release builds and local source builds run the same callback. Consumer
// builds download all three libraries, including the session finalizer.

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:kiln/kiln.dart';

import 'apple_compatibility.dart';
import 'source_build.dart';

void main(List<String> args) async {
  final lines = <String>[];
  void log(String message) => lines.add('[fonnx] $message');
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) {
      // A web build: install the web runtime files of native_artifacts/web.json
      // into the app (kiln ADR 002).
      return Kiln(input: input, output: output, log: log).installWeb();
    }
    final timer = Stopwatch()..start();
    await Kiln(
      input: fonnxCompatibilityInput(input),
      output: output,
      log: log,
    ).run((source) => buildFromSource(input, output, source, log));
    log('Hook completed in ${timer.elapsedMilliseconds}ms');
  }).whenComplete(() {
    if (lines.isNotEmpty) stderr.write(lines.join('\n'));
  });
}
