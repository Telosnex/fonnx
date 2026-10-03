import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:convert';

import 'package:fonnx/dylib_path_overrides.dart';

import '../futo_swipe_types.dart';
import 'futo_swipe_engine.dart';
import 'futo_swipe_ort_backend.dart';

/// Owns the worker isolate that holds the ONNX sessions and lexicon.
final class FutoSwipeIsolateManager {
  Isolate? _isolate;
  SendPort? _sendPort;

  /// Returns the swipeable lexicon size.
  Future<int> start({
    required FutoSwipeBundle bundle,
    required List<FutoSwipeWord> lexicon,
    required bool includeModelVocabulary,
    required int beamWidth,
  }) async {
    if (_sendPort != null) {
      throw StateError('FUTO Swipe isolate already started');
    }
    final handshake = ReceivePort();
    try {
      _isolate = await Isolate.spawn(
        _entryPoint,
        handshake.sendPort,
        onError: handshake.sendPort,
        debugName: 'fonnx-futo-swipe',
      );
      final first = await handshake.first;
      if (first is! SendPort) {
        throw Exception('Failed to start FUTO Swipe isolate: $first');
      }
      _sendPort = first;
      return await _request<int>(
        _Initialize(
          bundle,
          lexicon,
          includeModelVocabulary,
          beamWidth,
          fonnxOrtDylibPathOverride,
        ),
      );
    } catch (_) {
      _isolate?.kill();
      _isolate = null;
      _sendPort = null;
      rethrow;
    } finally {
      handshake.close();
    }
  }

  Future<FutoSwipeEmissions> emissions(
    List<FutoSwipePoint> trace,
    FutoSwipeLayout layout,
  ) => _request(_Emissions(trace, layout));

  Future<List<FutoSwipeCandidate>> decode(
    List<FutoSwipePoint> trace,
    FutoSwipeLayout layout,
    List<String>? previousWords,
    int maxCandidates,
  ) => _request(_Decode(trace, layout, previousWords, maxCandidates));

  Future<List<double>> scoreWords(
    List<String> previousWords,
    List<String> words,
  ) => _request(_ScoreWords(previousWords, words));

  Future<List<FutoWordScore>> predictNextWords(
    List<String> previousWords,
    int count,
  ) => _request(_PredictNextWords(previousWords, count));

  Future<int> setLexicon(
    List<FutoSwipeWord> lexicon,
    bool includeModelVocabulary,
  ) => _request(_SetLexicon(lexicon, includeModelVocabulary));

  Future<void> close() async {
    if (_sendPort == null) return;
    try {
      await _request<void>(const _Close());
    } finally {
      _isolate?.kill();
      _isolate = null;
      _sendPort = null;
    }
  }

  Future<T> _request<T>(_Command command) async {
    final sendPort = _sendPort;
    if (sendPort == null) {
      throw StateError('FUTO Swipe isolate has not started');
    }
    final response = ReceivePort();
    try {
      sendPort.send(_Envelope(command, response.sendPort));
      final value = await response.first;
      if (value is _RemoteError) {
        throw Exception('${value.message}\n${value.stackTrace}');
      }
      return value as T;
    } finally {
      response.close();
    }
  }
}

void _entryPoint(SendPort handshake) {
  final receivePort = ReceivePort();
  handshake.send(receivePort.sendPort);
  FutoSwipeEngine? engine;

  receivePort.listen((dynamic message) async {
    if (message is! _Envelope) return;
    final command = message.command;
    try {
      switch (command) {
        case _Initialize():
          if (command.ortDylibOverride != null) {
            fonnxOrtDylibPathOverride = command.ortDylibOverride;
          }
          final bundle = command.bundle;
          final vocabulary = await File(bundle.vocabularyPath).readAsLines();
          final scoring =
              jsonDecode(await File(bundle.scoringPath).readAsString())
                  as Map<String, dynamic>;
          final backend = NativeFutoSwipeOnnxBackend(bundle);
          try {
            engine = await FutoSwipeEngine.create(
              backend: backend,
              vocabulary: vocabulary,
              scoring: scoring,
              lexicon: command.lexicon,
              includeModelVocabulary: command.includeModelVocabulary,
              beamWidth: command.beamWidth,
            );
          } catch (_) {
            await backend.close();
            rethrow;
          }
          message.reply.send(engine!.lexiconSize);
        case _Emissions():
          message.reply.send(
            await engine!.emissions(command.trace, command.layout),
          );
        case _Decode():
          message.reply.send(
            await engine!.decode(
              command.trace,
              command.layout,
              previousWords: command.previousWords,
              maxCandidates: command.maxCandidates,
            ),
          );
        case _ScoreWords():
          message.reply.send(
            await engine!.scoreWords(command.previousWords, command.words),
          );
        case _PredictNextWords():
          message.reply.send(
            await engine!.predictNextWords(
              command.previousWords,
              command.count,
            ),
          );
        case _SetLexicon():
          engine!.setLexicon(
            command.lexicon,
            includeModelVocabulary: command.includeModelVocabulary,
          );
          message.reply.send(engine!.lexiconSize);
        case _Close():
          await engine?.close();
          message.reply.send(null);
          receivePort.close();
      }
    } catch (error, stackTrace) {
      message.reply.send(_RemoteError(error.toString(), stackTrace.toString()));
    }
  });
}

sealed class _Command {
  const _Command();
}

final class _Initialize extends _Command {
  const _Initialize(
    this.bundle,
    this.lexicon,
    this.includeModelVocabulary,
    this.beamWidth,
    this.ortDylibOverride,
  );

  final FutoSwipeBundle bundle;
  final List<FutoSwipeWord> lexicon;
  final bool includeModelVocabulary;
  final int beamWidth;
  final String? ortDylibOverride;
}

final class _Emissions extends _Command {
  const _Emissions(this.trace, this.layout);
  final List<FutoSwipePoint> trace;
  final FutoSwipeLayout layout;
}

final class _Decode extends _Command {
  const _Decode(
    this.trace,
    this.layout,
    this.previousWords,
    this.maxCandidates,
  );
  final List<FutoSwipePoint> trace;
  final FutoSwipeLayout layout;
  final List<String>? previousWords;
  final int maxCandidates;
}

final class _ScoreWords extends _Command {
  const _ScoreWords(this.previousWords, this.words);
  final List<String> previousWords;
  final List<String> words;
}

final class _PredictNextWords extends _Command {
  const _PredictNextWords(this.previousWords, this.count);
  final List<String> previousWords;
  final int count;
}

final class _SetLexicon extends _Command {
  const _SetLexicon(this.lexicon, this.includeModelVocabulary);
  final List<FutoSwipeWord> lexicon;
  final bool includeModelVocabulary;
}

final class _Close extends _Command {
  const _Close();
}

final class _Envelope {
  const _Envelope(this.command, this.reply);
  final _Command command;
  final SendPort reply;
}

final class _RemoteError {
  const _RemoteError(this.message, this.stackTrace);
  final String message;
  final String stackTrace;
}
