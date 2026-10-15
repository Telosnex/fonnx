import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fonnx/models/kokoro/kokoro.dart';
import 'package:fonnx/models/kokoro/kokoro_ffi.dart' show kokoroWav;
import 'package:path_provider/path_provider.dart';

/// Native preview using a prepared local bundle. Playback is per WAV chunk;
/// production apps should feed KokoroChunk.samples to their continuous PCM sink.
class KokoroWidget extends StatefulWidget {
  const KokoroWidget({super.key});
  @override
  State<KokoroWidget> createState() => _KokoroWidgetState();
}

class _KokoroWidgetState extends State<KokoroWidget> {
  final _text = TextEditingController(
    text:
        'I read the book yesterday, and I will read it again tomorrow. '
        'Mr. Darcy paid \$5.99 for three tickets.',
  );
  final _player = AudioPlayer();
  Kokoro? _engine;
  StreamIterator<KokoroChunk>? _iterator;
  Completer<void>? _playing;
  String _voice = 'af_heart';
  String _status =
      'Select a directory prepared by tool/kokoro/prepare_bundle.dart.';
  bool _busy = false;
  int _epoch = 0;
  Future<void>? _playTask;

  void _update(String status) {
    if (mounted) setState(() => _status = status);
  }

  Future<void> _load() async {
    final directory = await FilePicker.platform.getDirectoryPath();
    if (directory == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final engine = await Kokoro.load(KokoroBundle.fromDirectory(directory));
      if (!mounted) {
        await engine.dispose();
        return;
      }
      await _engine?.dispose();
      _engine = engine;
      _update('Loaded American and British English.');
    } catch (e) {
      _update('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _speak() => _playTask = _runSpeak();

  Future<void> _runSpeak() async {
    final engine = _engine;
    if (engine == null) return;
    final epoch = ++_epoch;
    setState(() => _busy = true);
    Directory? temporary;
    StreamSubscription<void>? completion;
    final iterator = StreamIterator(engine.speak(_text.text, voice: _voice));
    _iterator = iterator;
    final timer = Stopwatch()..start();
    try {
      temporary = await (await getTemporaryDirectory()).createTemp(
        'kokoro_preview_',
      );
      var available = await iterator.moveNext();
      var count = 0;
      while (available && epoch == _epoch) {
        final chunk = iterator.current;
        final path = '${temporary.path}/${count++}.wav';
        await File(path).writeAsBytes(kokoroWav(chunk.samples));
        if (epoch != _epoch) break;
        final done = Completer<void>();
        _playing = done;
        completion = _player.onPlayerComplete.listen((_) {
          if (!done.isCompleted) done.complete();
        });
        // At most one future chunk is prefetched while the current one plays.
        final next = iterator.moveNext();
        // Attach an error handler immediately, even if it completes during playback.
        final nextResult = next.then<Object>(
          (value) => value,
          onError: (Object e) => e,
        );
        if (count == 1) _update('First audio: ${timer.elapsedMilliseconds} ms');
        await _player.play(DeviceFileSource(path));
        await done.future;
        await completion.cancel();
        completion = null;
        _playing = null;
        await File(path).delete();
        final result = await nextResult;
        if (result is! bool) throw result;
        available = result;
      }
    } catch (e) {
      if (epoch == _epoch) _update('$e');
    } finally {
      await completion?.cancel();
      await iterator.cancel();
      await _player.stop();
      if (temporary != null) await temporary.delete(recursive: true);
      if (epoch == _epoch) {
        _iterator = null;
        _playing = null;
        if (mounted) setState(() => _busy = false);
      }
    }
  }

  Future<void> _stop() async {
    _epoch++;
    if (!(_playing?.isCompleted ?? true)) _playing!.complete();
    await _player.stop();
    await _iterator?.cancel();
    _iterator = null;
    await _playTask;
    if (mounted) setState(() => _busy = false);
  }

  @override
  void dispose() {
    unawaited(
      _stop().then((_) async {
        await _engine?.dispose();
        await _player.dispose();
      }),
    );
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return const Text(
        'Kokoro streaming preview: native platforms only for now.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Kokoro English speech',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        TextField(controller: _text, maxLines: 4),
        DropdownButton<String>(
          value: _voice,
          onChanged: _busy ? null : (v) => setState(() => _voice = v!),
          items: const [
            DropdownMenuItem(
              value: 'af_heart',
              child: Text('American — Heart'),
            ),
            DropdownMenuItem(value: 'bf_emma', child: Text('British — Emma')),
          ],
        ),
        Wrap(
          spacing: 8,
          children: [
            ElevatedButton(
              onPressed: _busy ? null : _load,
              child: const Text('Select bundle'),
            ),
            ElevatedButton(
              onPressed: _busy || _engine == null ? null : _speak,
              child: const Text('Speak'),
            ),
            TextButton(
              onPressed: _busy ? _stop : null,
              child: const Text('Stop'),
            ),
          ],
        ),
        Text(_status),
        const Text(
          'Preview plays WAV chunks; continuous PCM playback belongs in the app.',
        ),
      ],
    );
  }
}
