import 'dart:async';
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

  /// Number of audio channels
  static const int kChannels = 2;

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

  // Used for normalization. Start with 1 to avoid division by zero.
  int maxObservedAmplitude = 1;
  String transcription = '';
  var lastVadState = <String, dynamic>{};
  bool stopped = false;
  Timer? stopForMaxDurationTimer;
  bool normalizeMicAudio;
  var _detectedSpeech = false;

  SttService({
    required this.vadModelPath,
    required this.whisperModelPath,
    this.maxDuration = const Duration(seconds: 10),
    this.maxSilenceDuration = const Duration(seconds: 1),
    this.voiceThreshold = kVadPIsVoiceThreshold,
    this.normalizeMicAudio = true,
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

    Uint8List buffer = Uint8List(0);
    final List<AudioFrame> frames = [];

    final audioStream = await audioRecorder.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      numChannels: kChannels,
      sampleRate: kSampleRate,
    ));

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

  Uint8List normalizeBuffer(Uint8List buffer) {
    final Int16List samples = buffer.buffer.asInt16List();
    for (int i = 0; i < samples.length; i++) {
      // Update maxObservedAmplitude
      maxObservedAmplitude = math.max(maxObservedAmplitude, samples[i].abs());

      // Apply normalization
      final normalizedSample = (samples[i] / maxObservedAmplitude) * 32767;
      samples[i] = normalizedSample.toInt().clamp(-32768, 32767);
    }
    // You need to convert back from Int16List to Uint8List
    return Uint8List.view(samples.buffer);
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
      final micBytes = buffer.sublist(
          index * frameSizeInBytes, (index + 1) * frameSizeInBytes);
      final Uint8List frameBytes;
      if (normalizeMicAudio) {
        // Normalize the buffer
        final normalizedBytes = normalizeBuffer(micBytes);
        if (_detectedSpeech) {
          print('Detected speech @ ${frames.length - 1}, normalizing buffer.');
          frameBytes = normalizedBytes;
        } else {
          // If no speech has been detected yet, don't normalize the buffer.
          // Otherwise, things get screwy because the VAD is only seeing 30 ms
          // chunks and the initial silence sounds really loud to it, and
          // its less confident in subsequent speech.
          frameBytes = micBytes;
        }
      } else {
        frameBytes = micBytes;
      }
      final frame = AudioFrame(bytes: frameBytes);
      frames.add(frame);
      final idx = frames.length - 1;
      vad.doInference(frameBytes, previousState: lastVadState).then((value) {
        lastVadState = value;
        final p = (value['output'] as Float32List).first;
        frames[idx].vadP = p;
        if (p >= voiceThreshold) {
          _detectedSpeech = true;
        }
        streamController.add(SttServiceResponse(
          transcription: transcription,
          audioFrames: frames,
        ));
        if (_shouldStopForSilence(frames)) {
          if (kDebugMode) {
            print('[SttService] Stopping due to silence.');
          }
          stop();
        }
      });
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
    final maxVadP = frames.map((frame) => frame.vadP ?? 0).reduce((a, b) {
      return a > b ? a : b;
    });
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
    final isSilenceThreshold = math.max(voiceThreshold, maxVadP * 0.25);
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
    // Using isSilent == false caused too many trancription errors.
    // The best technique is to keep _some_ silence.
    // For now, we'll simply send all audio. It doesn't make a huge difference
    // in inference budget for intended use case (voice assistant-like, audio
    // is short and designed to terminate quickly, where short and quickly is
    // < 30 seconds).
    final notSilentFrames =
        frames.where((frame) => frame.vadP != null).toList();
    // Make sure we have non-silent frames to process
    if (notSilentFrames.isNotEmpty) {
      final bytesToInfer = Uint8List.fromList(notSilentFrames
          .map((e) => e.bytes)
          .expand((element) => element)
          .toList());
      final wav = generateWavFile(
        bytesToInfer,
        bitsPerSample: kBitsPerSample,
        numChannels: kChannels,
        sampleRate: kSampleRate,
      );
      final result = await whisper.doInference(wav);
      // The if statement here is an interesting choice.
      // Whisper output tends to fluctuate, especially in the presence of
      // extended silence following speech, ex.
      // 1. "what time is it in beijing"
      // 2. "What time is it in Beijing?"
      // 3. "what time is it in beijing"
      // This is a nice heuristic that reduces fluctuation and 'rewards' the
      // lengthier version that's more likely to have diacritical marks, or will
      // advance past the length of the version with diagritical marks due to
      // more speech following silence.
      if (result.length > transcription.length) {
        transcription = result;
      }

      streamController.add(SttServiceResponse(
        transcription: transcription,
        audioFrames: frames,
      ));
    }

    if (stopped) {
      // Do one last inference and close the stream.
      final wav = wavFromFrames(
        frames: frames,
        minVadP: voiceThreshold,
      );
      final result = await whisper.doInference(wav);
      if (result.length > transcription.length) {
        transcription = result;
      }
      streamController.add(SttServiceResponse(
        transcription: transcription,
        audioFrames: frames,
      ));
      print('Final transcription: $transcription');
      streamController.close();
      return;
    } else {
      // Re-run the loop
      Future.delayed(Duration.zero,
          () => _whisperInferenceLoop(whisper, frames, streamController));
    }
  }
}

Uint8List wavFromFrames(
    {required List<AudioFrame> frames, required double minVadP}) {
  final bytes = frames
      .where((e) => e.vadP != null && e.vadP! >= minVadP)
      .map((e) => e.bytes)
      .expand((element) => element);
  return generateWavFile(
    Uint8List.fromList(bytes.toList()),
    bitsPerSample: SttService.kBitsPerSample,
    numChannels: SttService.kChannels,
    sampleRate: SttService.kSampleRate,
  );
}

Uint8List generateWavFile(
  List<int> pcmData, {
  required int bitsPerSample,
  required int numChannels,
  required int sampleRate,
  bool normalize = true,
}) {
  List<int> dataToUse = pcmData;
  if (normalize && bitsPerSample == 16) {
    // Normalization only for 16-bit samples here.
    dataToUse = normalizePcmData(pcmData,
        bitsPerSample: bitsPerSample,
        numChannels: numChannels,
        sampleRate: sampleRate);
  }
  final header = generateWavHeader(
    dataToUse.length,
    sampleRate: sampleRate,
    numChannels: numChannels,
    bitsPerSample: bitsPerSample,
  );
  final wavFile = Uint8List(header.length + dataToUse.length);
  wavFile.setAll(0, header);
  wavFile.setAll(header.length, dataToUse);
  return wavFile;
}

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
  buffer.setUint32(16, 16, Endian.little); // Subchunk1 size (16 for PCM)
  buffer.setUint16(20, 1, Endian.little); // Audio format (1 for PCM)
  buffer.setUint16(22, numChannels, Endian.little); // Number of channels
  buffer.setUint32(24, sampleRate, Endian.little); // Sample rate
  buffer.setUint32(28, byteRate, Endian.little); // Byte rate
  buffer.setUint16(32, blockAlign, Endian.little); // Block align
  buffer.setUint16(34, bitsPerSample, Endian.little); // Bits per sample

  // data subchunk
  buffer.setUint32(36, 0x64617461, Endian.big); // 'data'
  buffer.setUint32(
      40, pcmDataLength, Endian.little); // Subchunk2 size (PCM data size)

  return header;
}

List<int> normalizePcmData(
  List<int> pcmData, {
  required int bitsPerSample,
  required int numChannels,
  required int sampleRate,
}) {
  // Assuming pcmData is in the format of `List<int>` with 16 bits per sample.
  // Note: For simplicity, handling only 16 bits per sample. Adjust logic for other bit depths.
  assert(bitsPerSample == 16);

  // Step 1: Convert List<int> to a suitable List of samples.
  Int16List samples = Int16List(pcmData.length ~/ 2);
  for (int i = 0; i < samples.length; i++) {
    samples[i] = (pcmData[2 * i + 1] << 8) | pcmData[2 * i];
  }

  // Step 2: Finding the peak sample value.
  int peak = samples.fold(0, (int prev, elem) => math.max(prev, elem.abs()));

  // Step 3: Calculate normalization factor.
  final normalizationFactor = peak != 0 ? 32767 / peak : 0.0;
  print('Normalization factor: $normalizationFactor');

  // Step 4: Normalize samples.
  for (int i = 0; i < samples.length; i++) {
    samples[i] =
        (samples[i] * normalizationFactor).round().clamp(-32768, 32767);
  }

  // Step 5: Convert samples back to List<int> format.
  List<int> normalizedData = [];
  for (int i = 0; i < samples.length; i++) {
    normalizedData.add(samples[i] & 0xFF);
    normalizedData.add((samples[i] >> 8) & 0xFF);
  }

  return normalizedData;
}
