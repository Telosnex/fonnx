import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:fonnx/dylib_path_overrides.dart';

import '../keyword_spotter_types.dart';
import 'keyword_spotter_engine.dart';
import 'kws_ort_backend.dart';

final class KeywordSpotterIsolateManager {
  Isolate? _isolate;
  SendPort? _sendPort;
  Future<void>? _starting;

  Future<void> start({
    required KeywordSpotterBundle bundle,
    required List<KeywordPhrase> keywords,
    required int maxActivePaths,
    required int trailingBlankFrames,
  }) async {
    if (_sendPort != null) return;
    if (_starting != null) return _starting;
    final completer = Completer<void>();
    _starting = completer.future;
    final handshake = ReceivePort();
    try {
      _isolate = await Isolate.spawn(
        _entryPoint,
        handshake.sendPort,
        onError: handshake.sendPort,
      );
      final first = await handshake.first;
      if (first is! SendPort) {
        throw Exception('Failed to start keyword spotter isolate: $first');
      }
      _sendPort = first;
      await _request<void>(
        _InitializeMessage(
          bundle,
          keywords,
          maxActivePaths,
          trailingBlankFrames,
          fonnxOrtDylibPathOverride,
        ),
      );
      completer.complete();
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
      _isolate?.kill();
      _isolate = null;
      _sendPort = null;
      rethrow;
    } finally {
      handshake.close();
      _starting = null;
    }
  }

  Future<List<KeywordDetection>> accept(Float32List samples) =>
      _request<List<KeywordDetection>>(
        _AcceptMessage(TransferableTypedData.fromList(<TypedData>[samples])),
      );

  Future<List<KeywordDetection>> finish() =>
      _request<List<KeywordDetection>>(const _FinishMessage());

  Future<String> transcribe(Float32List samples) => _request<String>(
    _TranscribeMessage(TransferableTypedData.fromList(<TypedData>[samples])),
  );

  Future<void> setKeywords(List<KeywordPhrase> keywords) =>
      _request<void>(_SetKeywordsMessage(keywords));

  Future<void> reset() => _request<void>(const _ResetMessage());

  Future<void> close() async {
    if (_sendPort == null) return;
    try {
      await _request<void>(const _CloseMessage());
    } finally {
      _isolate?.kill();
      _isolate = null;
      _sendPort = null;
    }
  }

  Future<T> _request<T>(_Command command) async {
    final sendPort = _sendPort;
    if (sendPort == null) {
      throw StateError('Keyword spotter isolate has not started');
    }
    final response = ReceivePort();
    sendPort.send(_Envelope(command, response.sendPort));
    final value = await response.first;
    response.close();
    if (value is _RemoteError) {
      throw Exception('${value.message}\n${value.stackTrace}');
    }
    return value as T;
  }
}

void _entryPoint(SendPort handshake) {
  final receivePort = ReceivePort();
  handshake.send(receivePort.sendPort);
  KeywordSpotterEngine? engine;

  receivePort.listen((dynamic rawEnvelope) async {
    if (rawEnvelope is! _Envelope) return;
    final command = rawEnvelope.command;
    try {
      switch (command) {
        case _InitializeMessage():
          if (command.ortDylibOverride != null) {
            fonnxOrtDylibPathOverride = command.ortDylibOverride;
          }
          engine = KeywordSpotterEngine(
            backend: NativeKwsOnnxBackend(command.bundle),
            keywords: command.keywords,
            maxActivePaths: command.maxActivePaths,
            trailingBlankFrames: command.trailingBlankFrames,
          );
          rawEnvelope.reply.send(null);
        case _AcceptMessage():
          final samples = command.samples.materialize().asFloat32List();
          rawEnvelope.reply.send(await engine!.accept(samples));
        case _FinishMessage():
          rawEnvelope.reply.send(await engine!.finish());
        case _TranscribeMessage():
          final samples = command.samples.materialize().asFloat32List();
          rawEnvelope.reply.send(await engine!.transcribe(samples));
        case _SetKeywordsMessage():
          await engine!.setKeywords(command.keywords);
          rawEnvelope.reply.send(null);
        case _ResetMessage():
          await engine!.reset();
          rawEnvelope.reply.send(null);
        case _CloseMessage():
          await engine?.close();
          rawEnvelope.reply.send(null);
          receivePort.close();
      }
    } catch (error, stackTrace) {
      rawEnvelope.reply.send(
        _RemoteError(error.toString(), stackTrace.toString()),
      );
    }
  });
}

sealed class _Command {
  const _Command();
}

final class _InitializeMessage extends _Command {
  const _InitializeMessage(
    this.bundle,
    this.keywords,
    this.maxActivePaths,
    this.trailingBlankFrames,
    this.ortDylibOverride,
  );

  final KeywordSpotterBundle bundle;
  final List<KeywordPhrase> keywords;
  final int maxActivePaths;
  final int trailingBlankFrames;
  final String? ortDylibOverride;
}

final class _AcceptMessage extends _Command {
  const _AcceptMessage(this.samples);
  final TransferableTypedData samples;
}

final class _FinishMessage extends _Command {
  const _FinishMessage();
}

final class _TranscribeMessage extends _Command {
  const _TranscribeMessage(this.samples);
  final TransferableTypedData samples;
}

final class _SetKeywordsMessage extends _Command {
  const _SetKeywordsMessage(this.keywords);
  final List<KeywordPhrase> keywords;
}

final class _ResetMessage extends _Command {
  const _ResetMessage();
}

final class _CloseMessage extends _Command {
  const _CloseMessage();
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
