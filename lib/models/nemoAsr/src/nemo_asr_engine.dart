import 'dart:math' as math;
import 'dart:typed_data';

import '../nemo_asr.dart';
import 'nemo_asr_features.dart';
import 'nemo_asr_vocabulary.dart';

/// Runs the ONNX graphs of a NeMo model. A TDT backend keeps the encoder
/// output and the prediction network's state between calls.
abstract interface class NemoAsrOnnxBackend {
  /// Runs the encoder on [features], mel bins × [frames] values.
  ///
  /// For a CTC model, returns the log-probabilities: encoder frames ×
  /// vocabulary. For a TDT model, keeps the encoder output, starts the
  /// prediction network from the blank token, and returns the number of
  /// encoder frames as a list of one value.
  Future<Float32List> encode(Float32List features, int frames);

  /// TDT: the joiner's logits for encoder frame [frame] and the current
  /// prediction: vocabulary, then durations.
  Future<Float32List> joint(int frame);

  /// TDT: advances the prediction network by [token].
  Future<void> predict(int token);

  Future<void> close();
}

/// The blank of Parakeet TDT v3, its last token.
final parakeetTdtV3Blank = parakeetTdtV3Tokens.length - 1;

/// Durations of Parakeet TDT, in encoder frames, by joiner output index.
const _tdtDurations = [0, 1, 2, 3, 4];

/// Greedy decoding, as sherpa-onnx and NeMo do it.
final class NemoAsrEngine {
  NemoAsrEngine(this._backend, this.model);

  final NemoAsrOnnxBackend _backend;
  final NemoAsrModel model;

  /// Most tokens that the TDT decoder emits without moving to a later frame.
  static const maxTokensPerFrame = 5;

  List<String> get _vocabulary => switch (model) {
    NemoAsrModel.fastConformerCtcMultilingual => nemoCtcMultilingualTokens,
    NemoAsrModel.parakeetTdtV3 => parakeetTdtV3Tokens,
  };

  int get _melBins => switch (model) {
    NemoAsrModel.fastConformerCtcMultilingual => 80,
    NemoAsrModel.parakeetTdtV3 => 128,
  };

  Future<void> close() => _backend.close();

  Future<String> transcribe(Float32List samples) async =>
      decodeNemoAsrText(_vocabulary, await transcribeTokens(samples));

  Future<List<int>> transcribeTokens(Float32List samples) async {
    if (samples.length > nemoAsrMaxSamples) {
      throw ArgumentError.value(
        samples.length,
        'samples.length',
        'NemoAsr accepts at most ${nemoAsrMaxSamples ~/ nemoAsrSampleRate} '
            'seconds of audio',
      );
    }
    final padded = withNemoAsrLeadIn(samples);
    final tokens = await _run(padded);
    if (tokens.isNotEmpty || model != NemoAsrModel.parakeetTdtV3) {
      return tokens;
    }
    // TDT sometimes emits only blanks for speech that starts soon after the
    // first sample. More silence before it usually avoids that. Silence also
    // gives no tokens, so this costs a second run for silent audio.
    final more = Float32List(_retryLeadInSamples + padded.length)
      ..setAll(_retryLeadInSamples, padded);
    return _run(more);
  }

  /// The silence before the second TDT run: 500 ms.
  static const _retryLeadInSamples = nemoAsrSampleRate ~/ 2;

  Future<List<int>> _run(Float32List samples) async {
    final frames = nemoAsrFrames(samples.length);
    final features = nemoAsrLogMel(samples, _melBins);
    final encoded = await _backend.encode(features, frames);
    return switch (model) {
      NemoAsrModel.fastConformerCtcMultilingual => greedyCtc(
        encoded,
        _vocabulary.length,
      ),
      NemoAsrModel.parakeetTdtV3 => _greedyTdt(encoded.single.toInt()),
    };
  }

  Future<List<int>> _greedyTdt(int frames) async {
    final vocabulary = _vocabulary.length;
    final blank = vocabulary - 1;
    final tokens = <int>[];
    var tokensThisFrame = 0;
    var t = 0;
    while (t < frames) {
      final logits = await _backend.joint(t);
      if (logits.length != vocabulary + _tdtDurations.length) {
        throw StateError('Unexpected TDT joiner output ${logits.length}');
      }
      final token = _argmax(logits, 0, vocabulary);
      var skip =
          _tdtDurations[_argmax(logits, vocabulary, _tdtDurations.length)];
      if (token != blank) {
        tokens.add(token);
        await _backend.predict(token);
        tokensThisFrame++;
      }
      if (skip > 0) tokensThisFrame = 0;
      if (tokensThisFrame >= maxTokensPerFrame ||
          (token == blank && skip == 0)) {
        tokensThisFrame = 0;
        skip = 1;
      }
      t += skip;
    }
    return tokens;
  }
}

/// The quiet that [withNemoAsrLeadIn] ensures before speech: 250 ms.
const nemoAsrLeadInSamples = nemoAsrSampleRate ~/ 4;

const _quietFrame = 160;
// -35 dBFS, as an RMS of samples in [-1, 1].
const _quietRms = 0.01778279410038923;

/// Returns [samples] with silence before them, so that they start with at
/// least [nemoAsrLeadInSamples] of quiet: 10 ms frames below -35 dBFS RMS.
///
/// Both models lose words when speech starts at the first sample, as in a
/// tightly cut VAD segment. On 60 FLEURS sentences in each of 6 languages,
/// cut to 20 ms before the speech, WER went from 12.2% to 10.9% (CTC) and
/// from 8.5% to 7.7% (TDT), and TDT had 2 empty transcripts instead of 4.
/// Audio that already starts with quiet gets no silence; adding it did not
/// help there.
Float32List withNemoAsrLeadIn(Float32List samples) {
  var quiet = 0;
  while (quiet < nemoAsrLeadInSamples) {
    final end = math.min(quiet + _quietFrame, samples.length);
    if (end <= quiet) break;
    var squares = 0.0;
    for (var i = quiet; i < end; i++) {
      squares += samples[i] * samples[i];
    }
    if (math.sqrt(squares / (end - quiet)) >= _quietRms) break;
    quiet = end;
  }
  final missing = math.max(0, nemoAsrLeadInSamples - quiet);
  if (missing == 0) return samples;
  return Float32List(missing + samples.length)..setAll(missing, samples);
}

/// Greedy CTC: the best token of each frame, without repeats and blanks.
/// The blank is the last token.
List<int> greedyCtc(Float32List logProbabilities, int vocabulary) {
  if (logProbabilities.length % vocabulary != 0) {
    throw StateError('Unexpected CTC output ${logProbabilities.length}');
  }
  final blank = vocabulary - 1;
  final tokens = <int>[];
  var previous = -1;
  for (var o = 0; o < logProbabilities.length; o += vocabulary) {
    final token = _argmax(logProbabilities, o, vocabulary);
    if (token != previous && token != blank) tokens.add(token);
    previous = token;
  }
  return tokens;
}

int _argmax(Float32List values, int start, int count) {
  var best = 0;
  var bestValue = values[start];
  for (var i = 1; i < count; i++) {
    final value = values[start + i];
    if (value > bestValue) {
      bestValue = value;
      best = i;
    }
  }
  return best;
}

/// Joins SentencePiece tokens: `▁` starts a word. Special tokens, such as
/// `<unk>` and `<|nospeech|>`, are skipped.
String decodeNemoAsrText(List<String> vocabulary, List<int> tokens) {
  final out = StringBuffer();
  for (final id in tokens) {
    final token = vocabulary[id];
    if (token.startsWith('<') && token.endsWith('>')) continue;
    out.write(token.replaceAll('▁', ' '));
  }
  return out.toString().trim();
}
