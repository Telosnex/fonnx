import 'dart:async';
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fonnx/models/keyword_spotter/keyword_spotter.dart';
import 'package:fonnx_example/padding.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:record/record.dart';

class KeywordSpotterWidget extends StatefulWidget {
  const KeywordSpotterWidget({super.key});

  @override
  State<KeywordSpotterWidget> createState() => _KeywordSpotterWidgetState();
}

class _KeywordSpotterWidgetState extends State<KeywordSpotterWidget> {
  static const _modelFilenames = [
    'encoder-epoch-12-avg-2-chunk-16-left-64.int8.onnx',
    'decoder-epoch-12-avg-2-chunk-16-left-64.int8.onnx',
    'joiner-epoch-12-avg-2-chunk-16-left-64.int8.onnx',
  ];
  static const _defaultTelosnexSpokenForms = [
    'tell us next',
    'tell us nucks',
    'tell low snacks',
    'tell us next',
    'tell us nucks',
    'tell us necks',
  ];

  final _keywordController = TextEditingController(text: 'telosnex');
  final _spokenFormsController = TextEditingController(
    text: _defaultTelosnexSpokenForms.join(', '),
  );
  final _detectionLog = <String>[];
  var _hasDefaultTelosnexAliases = true;

  String? _error;
  String _activeKeyword = '';
  bool _listening = false;
  bool _busy = false;

  KeywordSpotter? _spotter;
  StreamSubscription<KeywordDetection>? _detectionSubscription;
  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _audioSubscription;
  BytesBuilder? _teachBuffer;

  @override
  void dispose() {
    _stopListening();
    _keywordController.dispose();
    _spokenFormsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        heightPadding,
        Text(
          'Keyword Spotter',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const Text(
          '5 MB model detects custom English wake phrases, changeable at '
          'runtime without training. By k2-fsa/sherpa-onnx.',
        ),
        heightPadding,
        Row(
          children: [
            SizedBox(
              width: 240,
              child: TextField(
                controller: _keywordController,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  labelText: 'Wake phrase (English)',
                ),
                onChanged: (_) {
                  if (_hasDefaultTelosnexAliases) {
                    _hasDefaultTelosnexAliases = false;
                    _spokenFormsController.clear();
                  }
                },
                onSubmitted: (_) => _applyKeyword(),
              ),
            ),
            widthPadding,
            ElevatedButton(
              onPressed: _listening && !_busy ? _applyKeyword : null,
              child: const Text('Apply'),
            ),
            widthPadding,
            ElevatedButton(
              onPressed: _busy
                  ? null
                  : _listening
                  ? _stopListening
                  : _startListening,
              child: Text(_listening ? 'Stop' : 'Listen'),
            ),
          ],
        ),
        heightPadding,
        Wrap(
          spacing: padding,
          runSpacing: padding,
          crossAxisAlignment: WrapCrossAlignment.start,
          children: [
            SizedBox(
              width: 360,
              child: TextField(
                controller: _spokenFormsController,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  labelText: 'Sounds like (optional, comma-separated)',
                  helperText: 'Names may need phonetic aliases.',
                ),
                onChanged: (_) => _hasDefaultTelosnexAliases = false,
                onSubmitted: (_) => _applyKeyword(),
              ),
            ),
            Tooltip(
              message:
                  'Say the phrase; the model transcribes what it heard and '
                  'adds it as an alias.',
              child: ElevatedButton(
                onPressed: _busy ? null : _teachPronunciation,
                child: const Text('Teach by voice'),
              ),
            ),
          ],
        ),
        if (_listening) ...[
          heightPadding,
          Text('Listening for: "$_activeKeyword"'),
        ],
        if (_error != null) ...[
          heightPadding,
          Text(_error!, style: const TextStyle(color: Colors.red)),
        ],
        if (_detectionLog.isNotEmpty) ...[
          heightPadding,
          for (final line in _detectionLog.reversed.take(5)) Text(line),
        ],
      ],
    );
  }

  Future<void> _startListening() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final phrase = _keywordController.text.trim();
      final spotter = await KeywordSpotter.load(
        bundle: await _getBundle(),
        keywords: [_buildKeywordPhrase(phrase)],
        maxActivePaths: 16,
      );
      _spotter = spotter;
      _detectionSubscription = spotter.detections.listen((event) {
        final seconds = event.detectedAt.inMilliseconds / 1000;
        setState(() {
          _detectionLog.add(
            '✔ "${event.phrase}" at ${seconds.toStringAsFixed(2)}s '
            '(p=${event.meanTokenProbability.toStringAsFixed(2)})',
          );
        });
      });

      final recorder = AudioRecorder();
      if (!await recorder.hasPermission()) {
        throw 'Denied permission to record audio.';
      }
      _recorder = recorder;
      final audioStream = await recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          numChannels: 1,
          sampleRate: 16000,
          echoCancel: false,
          noiseSuppress: false,
        ),
      );
      _audioSubscription = audioStream.listen((bytes) {
        final teachBuffer = _teachBuffer;
        if (teachBuffer != null) {
          teachBuffer.add(bytes);
          return;
        }
        // Fire and forget; the spotter serializes operations internally.
        unawaited(
          _spotter?.acceptPcm16(bytes).catchError((Object e) {
            debugPrint('KWS accept error: $e');
          }),
        );
      });
      setState(() {
        _listening = true;
        _activeKeyword = phrase;
      });
    } catch (e) {
      setState(() => _error = '$e');
      await _stopListening();
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _applyKeyword() async {
    final spotter = _spotter;
    if (spotter == null) return;
    final phrase = _keywordController.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await spotter.setKeywords([_buildKeywordPhrase(phrase)]);
      setState(() {
        _activeKeyword = phrase;
        _detectionLog.add('→ now listening for "$phrase"');
      });
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _busy = false);
    }
  }

  /// Records ~3 seconds, asks the model what it heard, and adds that text
  /// as a pronunciation alias. This is how users teach it names the English
  /// vocabulary spells differently than it sounds, such as Telosnex.
  Future<void> _teachPronunciation() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    KeywordSpotter? tempSpotter;
    AudioRecorder? tempRecorder;
    StreamSubscription<Uint8List>? tempSubscription;
    final buffer = BytesBuilder(copy: false);
    try {
      final liveSpotter = _spotter;
      if (liveSpotter != null) {
        // Reuse the live mic; divert its audio into the teach buffer.
        _teachBuffer = buffer;
      } else {
        tempRecorder = AudioRecorder();
        if (!await tempRecorder.hasPermission()) {
          throw 'Denied permission to record audio.';
        }
        final stream = await tempRecorder.startStream(
          const RecordConfig(
            encoder: AudioEncoder.pcm16bits,
            numChannels: 1,
            sampleRate: 16000,
            echoCancel: false,
            noiseSuppress: false,
          ),
        );
        tempSubscription = stream.listen(buffer.add);
      }
      setState(() => _detectionLog.add('🎙 say it now…'));
      await Future<void>.delayed(const Duration(seconds: 3));
      _teachBuffer = null;
      await tempSubscription?.cancel();
      await tempRecorder?.stop();

      final spotter =
          liveSpotter ??
          (tempSpotter = await KeywordSpotter.load(
            bundle: await _getBundle(),
            keywords: const [KeywordPhrase('placeholder')],
            maxActivePaths: 16,
          ));
      var pcm = buffer.takeBytes();
      if (pcm.length.isOdd) pcm = pcm.sublist(0, pcm.length - 1);
      final heard = await spotter.transcribePcm16(pcm);
      if (heard.isEmpty) {
        setState(() => _detectionLog.add('👂 heard nothing; try again'));
        return;
      }
      setState(() {
        _detectionLog.add('👂 heard "$heard"');
        _hasDefaultTelosnexAliases = false;
        final existing = _spokenFormsController.text.trim();
        _spokenFormsController.text = existing.isEmpty
            ? heard
            : '$existing, $heard';
      });
      if (liveSpotter != null) {
        // Transcription reset detection state; re-arm with the new alias.
        await _applyKeyword();
      }
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      _teachBuffer = null;
      await tempSubscription?.cancel();
      await tempRecorder?.dispose();
      await tempSpotter?.close();
      setState(() => _busy = false);
    }
  }

  KeywordPhrase _buildKeywordPhrase(String phrase) {
    final spokenForms = _spokenFormsController.text
        .split(',')
        .map((form) => form.trim())
        .where((form) => form.isNotEmpty)
        .toList(growable: false);
    return KeywordPhrase(phrase, spokenForms: spokenForms);
  }

  Future<void> _stopListening() async {
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    await _recorder?.stop();
    await _recorder?.dispose();
    _recorder = null;
    await _detectionSubscription?.cancel();
    _detectionSubscription = null;
    await _spotter?.close();
    _spotter = null;
    if (mounted) {
      setState(() => _listening = false);
    }
  }

  Future<KeywordSpotterBundle> _getBundle() async {
    if (kIsWeb) {
      return KeywordSpotterBundle.gigaSpeech3m(
        'assets/assets/models/keywordSpotter',
      );
    }
    Directory cacheDirectory;
    try {
      cacheDirectory = await path_provider.getApplicationSupportDirectory();
    } on MissingPluginException {
      // Running in a widget test on the host; plugins are unavailable.
      cacheDirectory = Directory(
        path.join(Directory.systemTemp.path, 'fonnx_example_kws'),
      );
    }
    for (final filename in _modelFilenames) {
      final file = File(path.join(cacheDirectory.path, filename));
      // Asset paths always use /, even on Windows.
      final assetData = await rootBundle.load(
        'assets/models/keywordSpotter/$filename',
      );
      final upToDate =
          await file.exists() && await file.length() == assetData.lengthInBytes;
      if (!upToDate) {
        await file.create(recursive: true);
        await file.writeAsBytes(
          assetData.buffer.asUint8List(
            assetData.offsetInBytes,
            assetData.lengthInBytes,
          ),
          flush: true,
        );
      }
    }
    return KeywordSpotterBundle.gigaSpeech3m(cacheDirectory.path);
  }
}
