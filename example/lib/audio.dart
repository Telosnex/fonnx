// The example's audio: microphone PCM and WAV playback through
// telosnex_audio (one engine for the app).
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:telosnex_audio/telosnex_audio.dart';

Future<AudioEngine>? _engine;

/// The app's engine, opened on first use.
Future<AudioEngine> audioEngine() => _engine ??= TelosnexAudio.open();

/// Asks for the microphone where the platform needs the app to (Android;
/// iOS and macOS ask on first capture; desktop and web need nothing here).
Future<bool> requestMicrophone() async {
  if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return true;
  return (await Permission.microphone.request()).isGranted;
}

/// Mono 16-bit PCM bytes from the microphone, at [sampleRate], until the
/// subscription is cancelled. Throws if the microphone is not allowed.
Future<Stream<Uint8List>> microphonePcm16({int sampleRate = 16000}) async {
  if (!await requestMicrophone()) {
    throw 'Denied permission to record audio.';
  }
  final engine = await audioEngine();
  late final StreamController<Uint8List> out;
  StreamSubscription<CaptureFrame>? frames;
  out = StreamController<Uint8List>(
    onListen: () async {
      frames = engine.capture.listen(
        (f) => out.add(
          f.pcm.buffer.asUint8List(f.pcm.offsetInBytes, f.pcm.lengthInBytes),
        ),
        onError: out.addError,
      );
      try {
        await engine.startCapture(CaptureConfig(sampleRate: sampleRate));
      } catch (e, s) {
        out.addError(e, s);
      }
    },
    onCancel: () async {
      await frames?.cancel();
      await engine.stopCapture();
    },
  );
  return out.stream;
}

/// Plays mono 16-bit PCM [wav] (a RIFF/WAVE file). Completes when it ends,
/// or when [stop] is called.
class WavPlayer {
  Track? _track;
  Completer<void>? _done;

  Future<void> play(Uint8List wav) async {
    await stop();
    final (rate, channels, pcm) = _parseWav(wav);
    final engine = await audioEngine();
    final track = engine.createTrack(
      PcmFormat(sampleRate: rate, channels: channels),
    );
    final done = _done = Completer<void>();
    _track = track;
    final events = track.events.listen((e) {
      if ((e is TrackEnded || e is TrackFailed) && !done.isCompleted) {
        done.complete();
      }
    });
    track
      ..write(pcm)
      ..endOfStream()
      ..play();
    await done.future;
    await events.cancel();
    if (identical(_track, track)) _track = null;
    await track.dispose();
  }

  Future<void> stop() async {
    final done = _done;
    if (done != null && !done.isCompleted) done.complete();
    final track = _track;
    _track = null;
    if (track != null) await track.flush();
  }

  Future<void> dispose() => stop();
}

/// (sample rate, channels, samples) of a 16-bit PCM WAV.
(int, int, Int16List) _parseWav(Uint8List wav) {
  final d = ByteData.sublistView(wav);
  String id(int o) => String.fromCharCodes(wav.sublist(o, o + 4));
  if (id(0) != 'RIFF' || id(8) != 'WAVE') {
    throw const FormatException('Not a WAV file');
  }
  int? rate, channels;
  var o = 12;
  while (o + 8 <= wav.length) {
    final size = d.getUint32(o + 4, Endian.little);
    final body = o + 8;
    if (id(o) == 'fmt ') {
      if (d.getUint16(body, Endian.little) != 1 ||
          d.getUint16(body + 14, Endian.little) != 16) {
        throw const FormatException('Only 16-bit PCM WAV');
      }
      channels = d.getUint16(body + 2, Endian.little);
      rate = d.getUint32(body + 4, Endian.little);
    } else if (id(o) == 'data' && rate != null && channels != null) {
      final end = (body + size).clamp(body, wav.length);
      final pcm = Int16List((end - body) ~/ 2);
      for (var i = 0; i < pcm.length; i++) {
        pcm[i] = d.getInt16(body + i * 2, Endian.little);
      }
      return (rate, channels, pcm);
    }
    o = body + size + (size & 1);
  }
  throw const FormatException('WAV has no fmt or data chunk');
}
