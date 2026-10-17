import 'kokoro.dart';

Future<Kokoro> loadKokoro(KokoroBundle bundle, KokoroChunkPolicy policy) =>
    Future.error(
      UnsupportedError('Kokoro requires dart:io or dart:js_interop'),
    );
