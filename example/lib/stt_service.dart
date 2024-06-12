import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

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

class GetMicrophoneResponse {
  final Stream<Uint8List> audioStream;
  final AudioRecorder audioRecorder;

  GetMicrophoneResponse(
      {required this.audioStream, required this.audioRecorder});
}

class GetExistingBytesResponse {
  final Stream<Uint8List> audioStream;
  final StreamController<Uint8List> audioStreamController;

  GetExistingBytesResponse(
      {required this.audioStream, required this.audioStreamController});
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

  final sessionManager = WhisperSessionManager();

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
    Uint8List audioBuffer = Uint8List(0);
    final List<AudioFrame> frames = [];
    final getMicrophoneResponse = await _getMicrophoneStreamThrows();
    final audioStream = getMicrophoneResponse.audioStream;

    stopForMaxDurationTimer = Timer(maxDuration, () {
      debugPrint('[SttService] Stopping due to max duration.');
      stop();
      stopForMaxDurationTimer = null;
    });

    final vad = SileroVad.load(vadModelPath);
    var stoppedAudioRecorderForStoppedStream = false;
    audioStream.listen((event) {
      if (stopped && !stoppedAudioRecorderForStoppedStream) {
        stoppedAudioRecorderForStoppedStream = true;
        getMicrophoneResponse.audioRecorder.stop();
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
          transcription: sessionManager.transcription,
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
      final voiceFrames = sessionManager.getAudioFrames(
        frames: frames,
        voiceThresholdSegmentEnd: voiceThreshold,
      );
      if (voiceFrames.isEmpty) {
        return;
      }
      final bytesToInferBuilder = BytesBuilder(copy: false);
      for (final frame in voiceFrames) {
        bytesToInferBuilder.add(frame.bytes);
      }
      final bytesToInfer = bytesToInferBuilder.takeBytes();
      final result = (await whisper.doInference(bytesToInfer)).trim();
      sessionManager.addInferenceResult(result, voiceFrames.first);
      streamController.add(SttServiceResponse(
        transcription: sessionManager.transcription,
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

class WhisperSessionManager {
  var _frozenTranscription = '';
  String? _lastInferenceResult;
  AudioFrame? _lastFirstInferenceInputFrame;

  String get transcription {
    if (_lastInferenceResult != null && _lastInferenceResult!.isNotEmpty) {
      final StringBuffer sb = StringBuffer();
      sb.write(_frozenTranscription);
      sb.write(' ');
      sb.write(_lastInferenceResult);
      return sb.toString();
    }
    return _frozenTranscription;
  }

  List<AudioFrame> getAudioFrames({
    required List<AudioFrame> frames,
    required double voiceThresholdSegmentEnd,
  }) {
    var indexOfLastSegmentStart = -1;
    for (var i = frames.length - 1; i >= 0; i--) {
      final currentIndexInSegment =
          frames[i].vadP != null && frames[i].vadP! >= voiceThresholdSegmentEnd;
      final hasPreviousIndex = i - 1 >= 0;
      final previousIndexIsOutsideSegment = hasPreviousIndex &&
          frames[i - 1].vadP != null &&
          frames[i - 1].vadP! < voiceThresholdSegmentEnd;
      if (currentIndexInSegment && previousIndexIsOutsideSegment) {
        indexOfLastSegmentStart = i;
        break;
      }
    }

    final framesToInference = indexOfLastSegmentStart == -1
        ? <AudioFrame>[]
        : frames.sublist(math.max(0, indexOfLastSegmentStart - 3));
    return framesToInference;
  }

  void addInferenceResult(String result, AudioFrame firstInferenceInputFrame) {
    final lastResult = _lastInferenceResult;
    final isNewSegment = lastResult != null &&
        _lastFirstInferenceInputFrame != firstInferenceInputFrame;
    if (isNewSegment) {
      if (_frozenTranscription.isNotEmpty && lastResult.isNotEmpty) {
        _frozenTranscription += ' ';
      }
      _frozenTranscription += lastResult;
    }
    _lastFirstInferenceInputFrame = firstInferenceInputFrame;
    _lastInferenceResult = result;
  }
}

// Throws an error if the microphone stream cannot be obtained.
Future<GetMicrophoneResponse> _getMicrophoneStreamThrows() async {
  final audioRecorder = AudioRecorder();

  final hasPermission = await audioRecorder.hasPermission();
  if (!hasPermission) {
    throw 'Denied permission to record audio.';
  }

  final stream = await audioRecorder.startStream(
    const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      numChannels: SttService.kChannels,
      sampleRate: SttService.kSampleRate,
      echoCancel: false,
      noiseSuppress: false,
    ),
  );

  return GetMicrophoneResponse(
    audioStream: stream,
    audioRecorder: audioRecorder,
  );
}
