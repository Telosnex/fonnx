import 'dart:async';
import 'dart:typed_data';

import 'package:fonnx/models/sileroVad/silero_vad.dart';
import 'package:fonnx/models/whisper/whisper.dart';
import 'package:record/record.dart';

class SttServiceResponse {
  final String transcription;
  final List<AudioFrame?> audioFrames;

  SttServiceResponse({required this.transcription, required this.audioFrames});
}

class SttService {
  /// Format of audio bytes from microphone.
  // Rationale for PCM:
  // - PCM streaming is universally supported on all platforms.
  // - Streaming is not supported for all other codecs.
  // - Not all codecs are supported on all platforms.
  // - Whisper input expects at least WAV/MP3, and PCM is trival to convert
  //   to WAV. (only requires adding header)
  // - Observed when using `record` package on 2024 Feb 2.
  static const kEncoder = AudioEncoder.pcm16bits;

  /// Sample rate in Hz
  static const int kSampleRate = 16000;

  /// Number of audio channels
  static const int kChannels = 2;

  /// Bits per sample, assuming 16-bit PCM audio
  static const int kBitsPerSample = 16;

  /// Maximum VAD frame duration in milliseconds
  static const int kMaxVadFrameMs = 30;

  // Calculate frame size in bytes
  int calculateFrameSize() {
    return ((kSampleRate / 1000) *
            kMaxVadFrameMs *
            kChannels *
            (kBitsPerSample ~/ 8))
        .toInt();
  }

  final Duration maxDuration;
  final String vadModelPath;

  /// The floor value for VAD output to be considered speech.
  ///
  /// The VAD outputs a float from 0 to 1, representing the probability that
  /// the frame contains speech. >= this value is considered speech when
  /// deciding which frames to keep and when to stop recording, and also
  /// the value of the [AudioFrame.isSilent].
  final double vadOutputIsSpeechFloor;
  final String whisperModelPath;

  SttService({
    required this.vadModelPath,
    required this.whisperModelPath,
    this.vadOutputIsSpeechFloor = 0.1,
    this.maxDuration = const Duration(seconds: 10),
  });

  // Stream<SttServiceResponse> transcribe() {
  //   final StreamController<SttServiceResponse> controller =
  //       StreamController<SttServiceResponse>();
  //   _start(controller);
  //   return controller.stream;
  // }

  // void _start(StreamController<SttServiceResponse> streamController) async {
  //   // 1. Initialize models.
  //   final vad = SileroVad.load(vadModelPath);
  //   final whisper = Whisper.load(whisperModelPath);
  //   final audioRecorder = AudioRecorder();

  //   final hasPermission = await audioRecorder.hasPermission();
  //   if (!hasPermission) {
  //     streamController.addError('Denied permission to record audio.');
  //     streamController.close();
  //     return;
  //   }

  //   // Calculate frame size in bytes.
  //   const bytesPerSample = 2; // 16-bit PCM.
  //   const frameSizeInBytes =
  //       kSampleRate * kMaxVadFrameMs * kChannels * bytesPerSample ~/ 1000;

  //   // Buffer to collect bytes.
  //   Uint8List buffer = Uint8List(0);

  //   final numberOfFrames = (maxDuration.inMilliseconds / kMaxVadFrameMs).ceil();
  //   final frames = List<AudioFrame?>.filled(numberOfFrames, null);
  //   var nextFrameIndex = 0;

  //   const config = RecordConfig(
  //     encoder: AudioEncoder.pcm16bits,
  //     numChannels: kChannels,
  //     sampleRate: kSampleRate, // VAD natively supports 8kHz and 16kHz.
  //   );

  //   final audioStream = await audioRecorder.startStream(config);
  //   audioStream.listen((event) {
  //     // Append incoming bytes to the buffer.
  //     buffer = Uint8List.fromList(buffer + event); // Concatenate buffers.
  //     var receivedFrameCount = 0;
  //     var startedWhisperRunLoop = false;
  //     var whisperLoopTimer;
  //     // Process complete frames within the buffer.
  //     while (buffer.length >= frameSizeInBytes) {
  //       // Remove from from buffer.
  //       Uint8List frameBytes = buffer.sublist(0, frameSizeInBytes.toInt());
  //       buffer = Uint8List.fromList(buffer.sublist(frameSizeInBytes.toInt()));
  //       // Use bytes to create frame, start VAD async.
  //       final audioFrame = AudioFrame(bytes: frameBytes);
  //       final audioFrameIndex = nextFrameIndex;
  //       frames[nextFrameIndex] = audioFrame;
  //       if (nextFrameIndex == numberOfFrames - 1) {
  //         // All frames have been collected.
  //         _stop();
  //         break;
  //       }
  //       nextFrameIndex++;
  //       vad.doInference(frameBytes).then((value) {
  //         frames[audioFrameIndex]!.isSilent = value.first > 0.4;
  //         streamController.add(SttServiceResponse(
  //           transcription: '',
  //           audioFrames: frames,
  //         ));
  //       });
  //       receivedFrameCount++;
  //       // Intent: 90 ms,
  //       if (receivedFrameCount == (90 / kMaxVadFrameMs).floor() &&
  //           !startedWhisperRunLoop) {
  //         whisperLoopTimer ??=
  //             Timer.periodic(const Duration(milliseconds: 400), (timer) {
  //           _doWhisperInference(whisper, frames, streamController);
  //         });
  //       }
  //     }
  //   });
  // }

  String transcription = "";

  Stream<SttServiceResponse> transcribe() {
    final StreamController<SttServiceResponse> controller =
        StreamController<SttServiceResponse>();
    _start(controller);
    return controller.stream;
  }

  void _start(StreamController<SttServiceResponse> streamController) async {
    final audioRecorder = AudioRecorder();

    final hasPermission = await audioRecorder.hasPermission();
    if (!hasPermission) {
      streamController.addError('Denied permission to record audio.');
      streamController.close();
      return;
    }

    Uint8List buffer = Uint8List(0);
    final List<AudioFrame> frames = [];

    final audioStream = await audioRecorder.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      numChannels: kChannels,
      sampleRate: kSampleRate,
    ));
    final vad = SileroVad.load(vadModelPath);
    audioStream.listen((event) {
      buffer = Uint8List.fromList(buffer + event);
      _processBufferAndVad(vad, buffer, frames, streamController);
      buffer = Uint8List(0); // Clear the buffer after processing.
    });
    _whisperInferenceLoop(
      Whisper.load(whisperModelPath),
      frames,
      streamController,
    );
  }

  void _processBufferAndVad(
      SileroVad vad,
      Uint8List buffer,
      List<AudioFrame> frames,
      StreamController<SttServiceResponse> streamController) {
    // Process buffer into frames for VAD
    final frameSizeInBytes =
        (kSampleRate * kMaxVadFrameMs * kChannels * (kBitsPerSample / 8))
                .toInt() ~/
            1000;
    int index = 0;
    while ((index + 1) * frameSizeInBytes <= buffer.length) {
      final frameBytes = buffer.sublist(
          index * frameSizeInBytes, (index + 1) * frameSizeInBytes);
      final frame = AudioFrame(bytes: frameBytes);
      frames.add(frame);
      final idx = frames.length - 1;
      vad.doInference(frameBytes).then((value) {
        final isSpeech = value.first >= vadOutputIsSpeechFloor;
        frames[idx].isSilent = !isSpeech;
        streamController.add(SttServiceResponse(
            transcription: transcription, audioFrames: frames));
      });
      index++;
    }
  }

  // Recursively run whisper inference on collected frames
  void _whisperInferenceLoop(Whisper whisper, List<AudioFrame> frames,
      StreamController<SttServiceResponse> streamController) async {
    final notSilentFrames =
        frames.where((frame) => frame.isSilent == false).toList();
    // Make sure we have non-silent frames to process
    if (notSilentFrames.isNotEmpty) {
      final bytesToInfer = Uint8List.fromList(notSilentFrames
          .map((e) => e.bytes)
          .expand((element) => element)
          .toList());
      final result = await whisper.doInference(bytesToInfer);
      transcription += result; // Assuming the result is properly formatted.
      streamController.add(SttServiceResponse(
          transcription: transcription, audioFrames: frames));
    }
    // Re-run the loop
    Future.delayed(Duration.zero,
        () => _whisperInferenceLoop(whisper, frames, streamController));
  }
}

/// A single frame of audio data.
///
/// Added to allow memoization of the VAD inference and subsequent clipping out
/// audio frames that are not speech. e.g. getting silence clipped out amounts
/// to frames.where(!isSilent).map(bytes).toList().
class AudioFrame {
  final Uint8List bytes;
  bool? isSilent;

  AudioFrame({required this.bytes});
}
