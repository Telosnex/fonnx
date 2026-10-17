import 'dart:async';

import '../kokoro.dart';
import 'kokoro_engine.dart';

/// The UI-side half of Kokoro. A [KokoroEngine] runs on a native isolate or
/// a web Worker; subclasses carry the requests to it.
abstract class KokoroWorkerClient extends Kokoro {
  KokoroWorkerClient(this.bundle);

  final KokoroBundle bundle;
  int _utterance = 0;
  Future<void> _queue = Future.value();

  @override
  Map<String, KokoroVoice> get voices => bundle.voices;

  /// Whether dispose has started.
  bool get isClosing;

  /// Whether the worker can still take a cancel request.
  bool get canCancel;

  Future<void> workerBegin(
    String text,
    String voice,
    double speed,
    bool normalize,
  );

  Future<KokoroEngineChunk?> workerNext();

  Future<void> workerCancel();

  @override
  void validateRequest(String voice, double speed) {
    if (isClosing) throw StateError('Kokoro is disposed');
    super.validateRequest(voice, speed);
  }

  @override
  Stream<KokoroChunk> renderUtterance(
    String text, {
    required String voice,
    required double speed,
    required bool normalize,
  }) {
    late StreamController<KokoroChunk> controller;
    final cancelled = Completer<void>();
    final finished = Completer<void>();
    Completer<void>? paused;
    var isCancelled = false;
    Future<void> produce() async {
      final previous = _queue;
      final release = Completer<void>();
      // Cancelling a queued request must not let the next request overtake
      // the still-active predecessor.
      _queue = previous.then((_) => release.future);
      var begun = false;
      var textSent = false;
      try {
        await Future.any([previous, cancelled.future]);
        if (isCancelled) return;
        await workerBegin(text, voice, speed, normalize);
        begun = true;
        while (!isCancelled) {
          if (paused != null) await paused!.future;
          if (isCancelled) break;
          final chunk = await workerNext();
          if (chunk == null || isCancelled) break;
          if (paused != null) await paused!.future;
          if (isCancelled) break;
          // One text unit is one utterance, even when its phonemes are
          // decoded in several parts.
          final first = !textSent;
          if (first) _utterance++;
          controller.add(
            KokoroChunk(
              samples: chunk.samples,
              utteranceId: _utterance,
              isFinal: chunk.isFinal,
              text: first ? text : null,
              phonemes: chunk.phonemes,
            ),
          );
          if (first) textSent = true;
          // Let subscription pause/cancel callbacks run before another decode.
          await Future<void>.delayed(Duration.zero);
        }
      } catch (e, st) {
        if (!isCancelled) controller.addError(e, st);
      } finally {
        try {
          if (begun && canCancel) await workerCancel();
        } catch (e, st) {
          if (!isCancelled) controller.addError(e, st);
        } finally {
          release.complete();
          finished.complete();
          unawaited(controller.close());
        }
      }
    }

    controller = StreamController<KokoroChunk>(
      sync: true,
      onListen: () {
        unawaited(produce());
      },
      onPause: () {
        paused ??= Completer<void>();
      },
      onResume: () {
        paused?.complete();
        paused = null;
      },
      onCancel: () {
        isCancelled = true;
        if (!cancelled.isCompleted) cancelled.complete();
        paused?.complete();
        paused = null;
        return finished.future;
      },
    );
    return controller.stream;
  }
}
