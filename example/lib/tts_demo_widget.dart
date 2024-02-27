import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fonnx_example/padding.dart';
import 'package:fonnx_example/stt_service.dart';
import 'package:fonnx_example/whisper_widget.dart';
import 'dart:async';
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:path/path.dart' as path;

class TtsDemoWidget extends StatefulWidget {
  const TtsDemoWidget({super.key});

  @override
  State<TtsDemoWidget> createState() => _TtsDemoWidgetState();
}

class _TtsDemoWidgetState extends State<TtsDemoWidget> {
  SttServiceResponse? _sttServiceResponse;
  StreamSubscription? _sttStreamSubscription;
  SttService? _sttService;
  var _sttIsVoiceThreshold = SttService.kVadPIsVoiceThreshold;

  @override
  Widget build(BuildContext context) {
    final lastVoiceFrameIndex = _sttServiceResponse?.audioFrames.lastIndexWhere(
      (element) {
        final threshold = element?.vadP;
        if (threshold == null) {
          return false;
        }
        return threshold > _sttIsVoiceThreshold;
      },
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Voice Assistant Query Demo',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const Text(
            'Mic to Silero VAD for voice detection and Whisper Tiny for STT.\nOther Whisper models are available and much higher quality.'),
        heightPadding,
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            ElevatedButton.icon(
              onPressed: _runVadDemo,
              icon: _sttService == null
                  ? const Icon(Icons.mic)
                  : const Icon(Icons.mic_off),
              label: _sttService == null
                  ? const Text('Listen')
                  : const Text('Stop'),
            ),
          ],
        ),
        if (_sttServiceResponse != null) ...[
          heightPadding,
          Text(
            _sttServiceResponse!.transcription,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          heightPadding,
          SizedBox(
            height: 100,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: _sttServiceResponse!.audioFrames.map((e) {
                final index = _sttServiceResponse!.audioFrames.indexOf(e);
                final Color color;
                if (e?.vadP == null) {
                  color = Colors.transparent;
                } else if (e!.vadP! > _sttIsVoiceThreshold) {
                  color = Colors.green;
                } else {
                  color = Colors.red;
                }
                return Flexible(
                  child: Tooltip(
                    showDuration: Duration.zero,
                    waitDuration: Duration.zero,
                    message: e?.vadP == null
                        ? 'not recorded yet'
                        : '${(e!.vadP! * 100).toStringAsFixed(0)}%\n@${index * SttService.kMaxVadFrameMs}ms',
                    child: Container(
                      constraints: const BoxConstraints(
                        minWidth: 0,
                        maxWidth: 10,
                      ),
                      height: 100 * (e?.vadP == null ? 1 : e!.vadP!),
                      color: color,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          if (lastVoiceFrameIndex != null && lastVoiceFrameIndex >= 0) ...[
            heightPadding,
            Text(
                'Last detected voice: @${lastVoiceFrameIndex * SttService.kMaxVadFrameMs}ms'),
            if (_sttService == null && _sttServiceResponse != null)
              Text(
                  'Endpointer: @${(_sttServiceResponse!.audioFrames.length - 1) * SttService.kMaxVadFrameMs}ms'),
          ],
          heightPadding,
          Text(
              'Voice threshold: ${(_sttIsVoiceThreshold * 100).toStringAsFixed(0)}%'),
          Slider(
            label: '${(_sttIsVoiceThreshold * 100).toStringAsFixed(0)}%',
            value: _sttIsVoiceThreshold,
            onChanged: (value) {
              setState(
                () {
                  _sttIsVoiceThreshold = value;
                },
              );
            },
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.play_arrow),
            label: const Text("Play"),
            onPressed: () async {
              final frames = _sttServiceResponse!.audioFrames;
              int? firstFrameIndex;
              int? lastFrameIndex;
              for (var i = 0; i < frames.length; i++) {
                final frame = frames[i];
                if (frame?.vadP == null) {
                  // Audio hasn't been processed.
                  continue; // Continues to next iteration if audio hasn't been processed, instead of breaking.
                }
                // Check for the first non-silent frame
                if (firstFrameIndex == null &&
                    frame!.vadP! > _sttIsVoiceThreshold) {
                  firstFrameIndex = i;
                }
                // Update the last non-silent frame index whenever a non-silent frame is encountered
                if (frame!.vadP! > _sttIsVoiceThreshold) {
                  lastFrameIndex = i;
                }
              }
// Return or perform further actions only if both first and last non-silent frames are found
              if (firstFrameIndex == null || lastFrameIndex == null) {
                return;
              }
              final framesToProcess = frames.sublist(
                math.max(firstFrameIndex - 3, 0),
                math.min(lastFrameIndex + 10, frames.length),
              );
              debugPrint(
                  'Detected ${framesToProcess.length} frames of voice (from ${frames.whereType<AudioFrame>().toList().length} of audio @ threshold $_sttIsVoiceThreshold)');
              final indexOfFirstSpeech = frames.indexWhere((frame) {
                return frame?.vadP != null &&
                    frame!.vadP! >= _sttIsVoiceThreshold;
              });
              // Intent: capture ~100ms of audio before the first speech.
              final startIndex = math.max(0, indexOfFirstSpeech - 3);
              final voiceFrames = frames.sublist(startIndex);

              Uint8List generateWavHeader(
                int pcmDataLength, {
                required int bitsPerSample,
                required int numChannels,
                required int sampleRate,
              }) {
                int fileSize = pcmDataLength +
                    44 -
                    8; // Add WAV header size except for 'RIFF' and its size field
                int byteRate = sampleRate * numChannels * bitsPerSample ~/ 8;
                int blockAlign = numChannels * bitsPerSample ~/ 8;

                var header = Uint8List(44);
                var buffer = ByteData.view(header.buffer);

                // RIFF header
                buffer.setUint32(0, 0x52494646, Endian.big); // 'RIFF'
                buffer.setUint32(4, fileSize, Endian.little);
                buffer.setUint32(8, 0x57415645, Endian.big); // 'WAVE'

                // fmt subchunk
                buffer.setUint32(12, 0x666d7420, Endian.big); // 'fmt '
                buffer.setUint32(
                    16, 16, Endian.little); // Subchunk1 size (16 for PCM)
                buffer.setUint16(
                    20, 1, Endian.little); // Audio format (1 for PCM)
                buffer.setUint16(
                    22, numChannels, Endian.little); // Number of channels
                buffer.setUint32(24, sampleRate, Endian.little); // Sample rate
                buffer.setUint32(28, byteRate, Endian.little); // Byte rate
                buffer.setUint16(32, blockAlign, Endian.little); // Block align
                buffer.setUint16(
                    34, bitsPerSample, Endian.little); // Bits per sample

                // data subchunk
                buffer.setUint32(36, 0x64617461, Endian.big); // 'data'
                buffer.setUint32(40, pcmDataLength,
                    Endian.little); // Subchunk2 size (PCM data size)

                return header;
              }

              Uint8List generateWavFile(
                List<int> pcmData, {
                required int bitsPerSample,
                required int numChannels,
                required int sampleRate,
              }) {
                final header = generateWavHeader(
                  pcmData.length,
                  sampleRate: sampleRate,
                  numChannels: numChannels,
                  bitsPerSample: bitsPerSample,
                );
                final wavFile = Uint8List(header.length + pcmData.length);
                wavFile.setAll(0, header);
                wavFile.setAll(header.length, pcmData);
                return wavFile;
              }

              /// Returns null if no frames are above the threshold.
              Uint8List? wavFromFrames(
                  {required List<AudioFrame> frames, required double minVadP}) {
                final bytes = frames
                    .where((e) => e.vadP != null && e.vadP! >= minVadP)
                    .map((e) => e.bytes)
                    .expand((element) => element);
                if (bytes.isEmpty) {
                  return null;
                }
                final bytesList = bytes.toList();
                return generateWavFile(
                  bytesList,
                  bitsPerSample: SttService.kBitsPerSample,
                  numChannels: SttService.kChannels,
                  sampleRate: SttService.kSampleRate,
                );
              }

              final playWav = wavFromFrames(
                frames: voiceFrames.nonNulls.toList(),
                minVadP: 0,
              );
              if (playWav == null) {
                debugPrint('No frames with voice, skipping WAV creation.');
                return;
              }
              if (kIsWeb) {
                String base64String = base64Encode(playWav);

                // Step 4: Create the data URL
                final url = 'data:audio/wav;base64,$base64String';
                final player = AudioPlayer();
                player.play(UrlSource(url));
              } else {
                final tempDir = await path_provider.getTemporaryDirectory();
                final playWavPath = path.join(tempDir.path, 'voice.wav');
                final playWavFile = File(playWavPath);
                await playWavFile.writeAsBytes(playWav);
                debugPrint('Wrote voice to $playWavPath');
                final player = AudioPlayer();
                player.play(DeviceFileSource(playWavPath));
              }
            },
          ),
        ]
      ],
    );
  }

  void _runVadDemo() async {
    if (_sttStreamSubscription != null) {
      setState(() {
        _sttStreamSubscription?.cancel();
        _sttStreamSubscription = null;
        _sttService?.stop();
        _sttService = null;
      });
      return;
    }
    final vadModelPath = await getModelPath('silero_vad.onnx');
    final whisperModelPath = await getWhisperModelPath('whisper_tiny.onnx');
    final service = SttService(
        vadModelPath: vadModelPath, whisperModelPath: whisperModelPath);
    _sttService = service;
    final subscription = service.transcribe().listen((event) {
      setState(() {
        _sttServiceResponse = event;
      });
    });
    _sttStreamSubscription = subscription;
    subscription.onDone(() {
      setState(() {
        _sttStreamSubscription = null;
        _sttService = null;
      });
    });
  }

  Future<String> getModelPath(String modelFilenameWithExtension) async {
    if (kIsWeb) {
      return 'assets/models/sileroVad/$modelFilenameWithExtension';
    }
    final assetCacheDirectory =
        await path_provider.getApplicationSupportDirectory();
    final modelPath =
        path.join(assetCacheDirectory.path, modelFilenameWithExtension);

    File file = File(modelPath);
    bool fileExists = await file.exists();
    final fileLength = fileExists ? await file.length() : 0;

    // Do not use path package / path.join for paths.
    // After testing on Windows, it appears that asset paths are _always_ Unix style, i.e.
    // use /, but path.join uses \ on Windows.
    final assetPath =
        'assets/models/sileroVad/${path.basename(modelFilenameWithExtension)}';
    final assetByteData = await rootBundle.load(assetPath);
    final assetLength = assetByteData.lengthInBytes;
    final fileSameSize = fileLength == assetLength;
    if (!fileExists || !fileSameSize) {
      debugPrint(
          'Copying model to $modelPath. Why? Either the file does not exist (${!fileExists}), '
          'or it does exist but is not the same size as the one in the assets '
          'directory. (${!fileSameSize})');
      debugPrint('About to get byte data for $modelPath');

      List<int> bytes = assetByteData.buffer.asUint8List(
        assetByteData.offsetInBytes,
        assetByteData.lengthInBytes,
      );
      debugPrint('About to copy model to $modelPath');
      try {
        if (!fileExists) {
          await file.create(recursive: true);
        }
        await file.writeAsBytes(bytes, flush: true);
      } catch (e) {
        debugPrint('Error writing bytes to $modelPath: $e');
        rethrow;
      }
      debugPrint('Copied model to $modelPath');
    }

    return modelPath;
  }
}
