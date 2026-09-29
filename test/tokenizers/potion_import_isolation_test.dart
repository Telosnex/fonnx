import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('MinishLab 8M import graph excludes the 32M vocabulary', () {
    final reachable = _packageLibraries(
      File('lib/models/minishLab/minish_lab.dart').absolute.uri,
    );
    expect(reachable, contains(endsWith('/potion_base_8m_vocab.dart')));
    expect(reachable, isNot(contains(endsWith('/potion_32m_vocab.dart'))));
    expect(reachable, isNot(contains(endsWith('/potion_32m_tokenizer.dart'))));
  });

  test('opt-in 32M tokenizer excludes the 8M vocabulary and model runtime', () {
    final reachable = _packageLibraries(
      File('lib/tokenizers/potion_32m_tokenizer.dart').absolute.uri,
    );
    expect(reachable, contains(endsWith('/potion_32m_vocab.dart')));
    expect(reachable, isNot(contains(endsWith('/potion_base_8m_vocab.dart'))));
    expect(reachable, isNot(contains(endsWith('/minish_lab.dart'))));
    expect(reachable, isNot(contains(endsWith('/ort.dart'))));
  });
}

/// Follow package-local imports/exports, including every conditional branch.
/// Checking reachability (not static-field initialization) matters for debug
/// builds: importing an unused vocabulary still loads its library and source.
Set<String> _packageLibraries(Uri entry) {
  final root = Directory('lib').absolute.uri;
  final visited = <String>{};
  final pending = [entry];
  final directives = RegExp(
    r'''^(?:import|export)\s+([^;]+);''',
    multiLine: true,
  );
  final quotedUris = RegExp(r'''['"]([^'"]+)['"]''');
  while (pending.isNotEmpty) {
    final uri = pending.removeLast();
    if (!visited.add(uri.toString())) continue;
    final source = File.fromUri(uri).readAsStringSync();
    for (final directive in directives.allMatches(source)) {
      for (final match in quotedUris.allMatches(directive.group(1)!)) {
        final target = match.group(1)!;
        if (target.startsWith('package:fonnx/')) {
          pending.add(root.resolve(target.substring('package:fonnx/'.length)));
        } else if (!Uri.parse(target).hasScheme) {
          pending.add(uri.resolve(target));
        }
      }
    }
  }
  return visited;
}
