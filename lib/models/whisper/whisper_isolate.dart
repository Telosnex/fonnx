import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:fonnx/dylib_path_overrides.dart';

import 'src/whisper_engine.dart';
import 'src/whisper_ort_backend.dart';
import 'whisper.dart';

/// Runs Whisper in a long-lived worker isolate, so decoding does not block
/// the UI isolate. The isolate keeps the ORT sessions loaded.
final class WhisperIsolateManager {
  Isolate? _isolate;
  SendPort? _sendPort;
  Future<void>? _starting;

  Future<void> start(WhisperBundle bundle) async {
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
        throw Exception('Failed to start the Whisper isolate: $first');
      }
      _sendPort = first;
      await _request<void>(
        _InitializeMessage(bundle, fonnxOrtDylibPathOverride),
      );
      completer.complete();
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
      // Nothing else waits on this future when the caller gets the error.
      unawaited(completer.future.catchError((_) {}));
      _isolate?.kill();
      _isolate = null;
      _sendPort = null;
      rethrow;
    } finally {
      handshake.close();
      _starting = null;
    }
  }

  Future<String> transcribe(Float32List samples) => _request<String>(
    _TranscribeMessage(TransferableTypedData.fromList(<TypedData>[samples])),
  );

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
    if (sendPort == null) throw StateError('Whisper isolate has not started');
    final response = ReceivePort();
    sendPort.send(_Envelope(command, response.sendPort));
    final value = await response.first;
    response.close();
    if (value is _RemoteError) {
      if (value.isArgumentError) throw ArgumentError(value.message);
      throw Exception('${value.message}\n${value.stackTrace}');
    }
    return value as T;
  }
}

void _entryPoint(SendPort handshake) {
  final receivePort = ReceivePort();
  handshake.send(receivePort.sendPort);
  WhisperEngine? engine;

  receivePort.listen((dynamic rawEnvelope) async {
    if (rawEnvelope is! _Envelope) return;
    final command = rawEnvelope.command;
    try {
      switch (command) {
        case _InitializeMessage():
          if (command.ortDylibOverride != null) {
            fonnxOrtDylibPathOverride = command.ortDylibOverride;
          }
          engine = WhisperEngine(NativeWhisperOnnxBackend(command.bundle));
          rawEnvelope.reply.send(null);
        case _TranscribeMessage():
          final samples = command.samples.materialize().asFloat32List();
          rawEnvelope.reply.send(await engine!.transcribe(samples));
        case _CloseMessage():
          await engine?.close();
          rawEnvelope.reply.send(null);
          receivePort.close();
      }
    } catch (error, stackTrace) {
      rawEnvelope.reply.send(
        _RemoteError(
          error is ArgumentError ? '${error.message}' : error.toString(),
          stackTrace.toString(),
          isArgumentError: error is ArgumentError,
        ),
      );
    }
  });
}

sealed class _Command {
  const _Command();
}

final class _InitializeMessage extends _Command {
  const _InitializeMessage(this.bundle, this.ortDylibOverride);

  final WhisperBundle bundle;
  final String? ortDylibOverride;
}

final class _TranscribeMessage extends _Command {
  const _TranscribeMessage(this.samples);
  final TransferableTypedData samples;
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
  const _RemoteError(
    this.message,
    this.stackTrace, {
    required this.isArgumentError,
  });

  final String message;
  final String stackTrace;
  final bool isArgumentError;
}
