import 'kokoro.dart';

Future<Kokoro> loadKokoro(KokoroBundle bundle, KokoroChunkPolicy policy) =>
    Future.error(
      UnsupportedError('Kokoro currently requires a native platform'),
    );
