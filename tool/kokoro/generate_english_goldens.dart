// Uses the existing Python reference generator, not the Dart implementation.
import 'dart:io';

Future<void> main() async {
  final python = Platform.environment['KOKORO_PYTHON'] ?? 'python3';
  for (final dialect in ['us', 'gb']) {
    final script = File('tool/kokoro/gen_misaki_golden.py')
        .readAsStringSync()
        .replaceAll(
          'british=False',
          'british=${dialect == 'gb' ? 'True' : 'False'}',
        );
    final temporary = File('build/kokoro/reference_$dialect.py');
    temporary.parent.createSync(recursive: true);
    // The reference resolves handwritten data relative to __file__.
    temporary.writeAsStringSync(
      "__file__ = 'tool/kokoro/gen_misaki_golden.py'\n$script",
    );
    final run = await Process.start(python, [
      temporary.path,
      'test/data/goldens/misaki_en_$dialect.json',
    ], mode: ProcessStartMode.inheritStdio);
    if (await run.exitCode != 0) {
      throw StateError('Reference generation failed: $dialect');
    }
  }
}
