import 'dart:io';
import 'dart:typed_data';

/// The text of [path], relative to test/.
Future<String> readTestText(String path) => File('test/$path').readAsString();

/// The bytes of [path], relative to test/.
Future<Uint8List> readTestBytes(String path) =>
    File('test/$path').readAsBytes();
