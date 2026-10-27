import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fonnx/models/kokoro/kokoro.dart';
import 'package:fonnx/models/kokoro/kokoro_tokens.dart' show kokoroWav;
import 'package:fonnx_example/audio.dart';
import 'package:fonnx_example/kokoro_models.dart';

/// Kokoro preview. It downloads the pinned bundle, or on native platforms
/// uses a local one. It plays one WAV per sentence. Production apps should
/// feed each KokoroChunk.samples to a continuous PCM sink, for the earliest
/// first audio.
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
  final _player = WavPlayer();
  Kokoro? _engine;
  StreamIterator<KokoroChunk>? _iterator;
  Completer<void>? _playing;
  String _voice = kokoroExampleVoices.first;
  String _status = 'Load downloads about 200 MB the first time.';
  bool _busy = false;
  int _epoch = 0;
  Future<void>? _playTask;

  void _update(String status) {
    if (mounted) setState(() => _status = status);
  }

  Future<void> _download() => _load(() async {
    final timer = Stopwatch()..start();
    final bundle = await kokoroExampleBundle(
      onProgress: (received, total) => _update(
        'Downloading: ${received ~/ 1000000} of ${total ~/ 1000000} MB',
      ),
    );
    _update('Loading models...');
    final engine = await Kokoro.load(bundle);
    _update('Loaded in ${timer.elapsedMilliseconds} ms.');
    return engine;
  });

  /// A directory prepared by tool/kokoro/prepare_bundle.dart.
  Future<void> _pickLocal() async {
    final directory = await FilePicker.platform.getDirectoryPath();
    if (directory == null) return;
    await _load(() async {
      final engine = await Kokoro.load(
        KokoroBundle.fromDirectory(directory, voiceNames: kokoroExampleVoices),
      );
      _update('Loaded $directory.');
      return engine;
    });
  }

  Future<void> _load(Future<Kokoro> Function() load) async {
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final engine = await load();
      if (!mounted) {
        await engine.dispose();
        return;
      }
      await _engine?.dispose();
      _engine = engine;
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
    final iterator = StreamIterator(engine.speak(_text.text, voice: _voice));
    _iterator = iterator;
    final timer = Stopwatch()..start();

    /// The samples of the next sentence, or null at the end. Chunks split a
    /// sentence mid-word, so they must play without gaps; one WAV per
    /// sentence does that. Sentences end in silence.
    Future<Float32List?> nextSentence() async {
      final samples = <double>[];
      while (await iterator.moveNext()) {
        samples.addAll(iterator.current.samples);
        if (iterator.current.isFinal) break;
      }
      return samples.isEmpty ? null : Float32List.fromList(samples);
    }

    try {
      var sentence = await nextSentence();
      var count = 0;
      while (sentence != null && epoch == _epoch) {
        count++;
        final done = Completer<void>();
        _playing = done;
        // The next sentence is synthesized while this one plays.
        final next = nextSentence();
        // Attach an error handler now, in case it fails during playback.
        final nextResult = next.then<Object?>(
          (value) => value,
          onError: (Object e) => e,
        );
        if (count == 1) _update('First audio: ${timer.elapsedMilliseconds} ms');
        await Future.any([_player.play(kokoroWav(sentence)), done.future]);
        if (!done.isCompleted) done.complete();
        _playing = null;
        final result = await nextResult;
        if (result is Object && result is! Float32List) throw result;
        sentence = result as Float32List?;
      }
    } catch (e) {
      if (epoch == _epoch) _update('$e');
    } finally {
      await iterator.cancel();
      await _player.stop();
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
    final loaded = _engine != null;
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
            if (!loaded)
              ElevatedButton(
                onPressed: _busy ? null : _download,
                child: const Text('Load'),
              ),
            if (!loaded && !kIsWeb)
              TextButton(
                onPressed: _busy ? null : _pickLocal,
                child: const Text('Use local bundle'),
              ),
            ElevatedButton(
              onPressed: _busy || !loaded ? null : _speak,
              child: const Text('Speak'),
            ),
            TextButton(
              onPressed: _busy && loaded ? _stop : null,
              child: const Text('Stop'),
            ),
          ],
        ),
        Text(_status),
      ],
    );
  }
}
