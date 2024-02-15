import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:fonnx/models/sileroVad/silero_vad.dart';
import 'package:fonnx/models/whisper/whisper.dart';
import 'package:record/record.dart';

/// A single frame of audio data.
///
/// Added to allow memoization of the VAD inference and subsequent clipping out
/// audio frames that are not speech. e.g. getting silence clipped out amounts
/// to frames.where(!isSilent).map(bytes).toList().
class AudioFrame {
  final Uint8List bytes;

  /// Probability that the frame contains speech.
  ///
  /// The VAD outputs a float from 0 to 1, representing the probability that
  /// the frame contains speech. >= this value is considered speech when
  /// deciding which frames to keep and when to stop recording, and also
  /// the value of the [AudioFrame.isSilent].
  double? vadP;
  AudioFrame({required this.bytes});
}

class SttServiceResponse {
  final String transcription;
  final List<AudioFrame?> audioFrames;

  SttServiceResponse({required this.transcription, required this.audioFrames});
}

class SttService {
  // Rationale for PCM:
  // - PCM streaming is universally supported on all platforms.
  // - Streaming is not supported for all other codecs.
  // - Not all codecs are supported on all platforms.
  // - Whisper input expects at least WAV/MP3, and PCM is trival to convert
  //   to WAV. (only requires adding header)
  // - Observed when using `record` package on 2024 Feb 2.
  /// Format of audio bytes from microphone.
  static const kEncoder = AudioEncoder.pcm16bits;

  /// Sample rate in Hz
  static const int kSampleRate = 16000;

  // Rationale for 1 channel:
  // - Whisper needs ORT Extensions in order to decode anything other than
  // signed 16-bit PCM audio in 1 channel at 16kHz.
  // - ORT Extensions are not supported on web.
  // - Generally, 1 channel is sufficient for speech recognition, it is
  //   both best practice and supported universally.
  /// Number of audio channels
  static const int kChannels = 1;

  /// Bits per sample, assuming 16-bit PCM audio
  static const int kBitsPerSample = 16;

  /// Maximum VAD frame duration in milliseconds
  static const int kMaxVadFrameMs = 30;

  /// Recommended VAD probability threshold for speech.
  /// Tuned to accept whispering.
  static const double kVadPIsVoiceThreshold = 0.1;

  final Duration maxDuration;

  /// If and only if:
  /// - There was at least one frame of speech, and
  /// - The last N frames were silent and their duration is >= this value,
  /// then the recording will stop.
  final Duration maxSilenceDuration;
  final String vadModelPath;
  final String whisperModelPath;

  /// Values >= this are considered speech.
  ///
  /// The VAD outputs a float from 0 to 1, representing the probability that
  /// the frame contains speech. >= this value is considered speech when
  /// deciding which frames to keep and when to stop recording.
  final double voiceThreshold;
  String transcription = '';
  var lastVadState = <String, dynamic>{};
  var lastVadStateIndex = 0;
  bool stopped = false;
  Timer? stopForMaxDurationTimer;

  SttService({
    required this.vadModelPath,
    required this.whisperModelPath,
    this.maxDuration = const Duration(seconds: 10),
    this.maxSilenceDuration = const Duration(milliseconds: 1000),
    this.voiceThreshold = kVadPIsVoiceThreshold,
  });

  Stream<SttServiceResponse> transcribe() {
    final StreamController<SttServiceResponse> controller =
        StreamController<SttServiceResponse>();
    _start(controller);
    return controller.stream;
  }

  void stop() {
    stopForMaxDurationTimer?.cancel();
    stopped = true;
  }

  void _start(StreamController<SttServiceResponse> streamController) async {
    final audioRecorder = AudioRecorder();

    final hasPermission = await audioRecorder.hasPermission();
    if (!hasPermission) {
      streamController.addError('Denied permission to record audio.');
      streamController.close();
      return;
    }

    Uint8List audioBuffer = Uint8List(0);
    final List<AudioFrame> frames = [];

    final audioStream = await audioRecorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        numChannels: kChannels,
        sampleRate: kSampleRate,
        echoCancel: false,
        noiseSuppress: false));

    stopForMaxDurationTimer = Timer(maxDuration, () {
      stop();
      stopForMaxDurationTimer = null;
    });

    final vad = SileroVad.load(vadModelPath);
    var stoppedAudioRecorderForStoppedStream = false;
    audioStream.listen((event) {
      if (stopped && !stoppedAudioRecorderForStoppedStream) {
        stoppedAudioRecorderForStoppedStream = true;
        audioRecorder.stop();
        return;
      }
      audioBuffer = Uint8List.fromList(audioBuffer + event);
      const maxVadFrameSizeInBytes = kSampleRate *
          kMaxVadFrameMs *
          kChannels *
          (kBitsPerSample / 8) ~/
          1000;
      final remainder = audioBuffer.length % maxVadFrameSizeInBytes;
      final vadBufferLength = audioBuffer.length - remainder;
      final vadBuffer = audioBuffer.sublist(0, vadBufferLength);
      _vadBufferQueue.add(vadBuffer);
      audioBuffer = audioBuffer.sublist(vadBufferLength);
    });
    _vadInferenceLoop(vad, frames, streamController);
    _whisperInferenceLoop(
      Whisper.load(whisperModelPath),
      frames,
      streamController,
    );
  }

  final Queue<Uint8List> _vadBufferQueue = Queue<Uint8List>();
  void _vadInferenceLoop(
    SileroVad vad,
    List<AudioFrame> frames,
    StreamController<SttServiceResponse> streamController,
  ) async {
    if (stopped) {
      return;
    }
    final hasBuffer = _vadBufferQueue.isNotEmpty;
    if (hasBuffer) {
      final buffer = _vadBufferQueue.removeFirst();
      await _processBufferAndVad(vad, buffer, frames, streamController);
      _vadInferenceLoop(vad, frames, streamController);
    } else {
      Future.delayed(const Duration(milliseconds: kMaxVadFrameMs),
          () => _vadInferenceLoop(vad, frames, streamController));
    }
  }

  Future<void> _processBufferAndVad(
      SileroVad vad,
      Uint8List buffer,
      List<AudioFrame> frames,
      StreamController<SttServiceResponse> streamController) async {
    // Process buffer into frames for VAD
    final frameSizeInBytes =
        (kSampleRate * kMaxVadFrameMs * kChannels * (kBitsPerSample / 8))
                .toInt() ~/
            1000;
    int index = 0;
    while ((index + 1) * frameSizeInBytes <= buffer.length) {
      final startIdx = index * frameSizeInBytes;
      final endIdx = (index + 1) * frameSizeInBytes;
      final frameBytes = buffer.sublist(startIdx, endIdx);
      final frame = AudioFrame(bytes: frameBytes);
      frames.add(frame);
      final idx = frames.length - 1;
      final nextVdState =
          await vad.doInference(frameBytes, previousState: lastVadState);
      lastVadState = nextVdState;
      lastVadStateIndex = idx;
      final p = (nextVdState['output'] as Float32List).first;
      frames[idx].vadP = p;
      if (!stopped) {
        streamController.add(SttServiceResponse(
          transcription: transcription,
          audioFrames: frames,
        ));
      } else {
        break;
      }

      if (_shouldStopForSilence(frames)) {
        if (kDebugMode) {
          print('[SttService] Stopping due to silence.');
        }
        stop();
      }
      index++;
    }
  }

  bool _shouldStopForSilence(List<AudioFrame> frames) {
    if (frames.isEmpty) {
      return false;
    }
    final frameThatIsSpeech = frames.any((frame) {
      return frame.vadP != null && frame.vadP! >= voiceThreshold;
    });
    if (!frameThatIsSpeech) {
      return false;
    }
    // There's an asymmetry with voiceThreshold due to VAD behavior.
    //
    // At start speech, it behooves voiceThreshold to be low enough to capture
    // a whisper.
    //
    // At end speech, the VAD tends to exponentially decay its output in the
    // presence of pure silence. This can take ~3 seconds and tends to increase
    // with query volume.
    //
    // We can't rely on the exponential decay being strictly monotonic: there's
    // small fluctuations in the output. Smoothing could be an option.
    //
    // A simpler approach of using a threshold that's a fraction of the max
    // VAD output is used here. That works astonishingly well across test cases
    // of whispering, speaking, and speaking strongly.
    final isSilenceThreshold = voiceThreshold;
    final lastNFrames = frames.reversed.takeWhile((frame) {
      return frame.vadP != null && frame.vadP! < isSilenceThreshold;
    }).toList();
    final lastNSilenceDuration = lastNFrames.length * kMaxVadFrameMs;
    return lastNSilenceDuration >= maxSilenceDuration.inMilliseconds;
  }

  // Recursively run whisper inference on collected frames
  void _whisperInferenceLoop(
    Whisper whisper,
    List<AudioFrame> frames,
    StreamController<SttServiceResponse> streamController,
  ) async {

    Future<void> doIt() async {
      final indexOfFirstSpeech = frames.indexWhere((frame) {
        return frame.vadP != null && frame.vadP! >= voiceThreshold;
      });
      // Intent: capture ~100ms of audio before the first speech.
      final startIndex = math.max(0, indexOfFirstSpeech - 3);
      final voiceFrames = indexOfFirstSpeech == -1
          ? <AudioFrame>[]
          : frames.sublist(startIndex);
      if (voiceFrames.isEmpty) {
        return;
      }

      final bytesToInfer = Uint8List.fromList(voiceFrames
          .map((e) => e.bytes)
          .expand((element) => element)
          .toList());
      final result = (await whisper.doInference(bytesToInfer)).trim();
      // Whisper output tends to fluctuate, especially in the presence of
      // extended silence following speech, ex.
      // 1. "what time is it in beijing"
      // 2. "What time is it in Beijing?"
      // 3. "what time is it in beijing"
      // This is a nice heuristic that reduces fluctuation and 'rewards' the
      // lengthier version that's more likely to have diacritical marks.
      //
      // A weak point is this presumes any additional coherent speech will end
      // up increasing the length of the transcription. Theoratically, maybe
      // this doesn't happen: ex. "What time is it in Beijing????????"
      // "What time is it in Beijing, China?".
      if (result.length > transcription.length) {
        transcription = result;
      }

      streamController.add(SttServiceResponse(
        transcription: transcription,
        audioFrames: frames,
      ));
    }

    void scheduleNextInference() async {
      if (!stopped) {
        Future.delayed(const Duration(milliseconds: 16),
            () => _whisperInferenceLoop(whisper, frames, streamController));
        return;
      }
      // Stopped.
      // Do one last inference with all audio bytes, then close the stream.
      await doIt();
      streamController.close();
    }


    await doIt();
    scheduleNextInference();
  }
}