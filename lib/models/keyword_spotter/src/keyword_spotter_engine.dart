import 'dart:typed_data';

import '../keyword_spotter_types.dart';
import 'context_graph.dart';
import 'english_tokenizer.dart';
import 'streaming_fbank.dart';
import 'transducer_decoder.dart';

final class KeywordSpotterEngine {
  KeywordSpotterEngine({
    required KwsOnnxBackend backend,
    required List<KeywordPhrase> keywords,
    int maxActivePaths = 4,
    int trailingBlankFrames = 1,
  }) : _backend = backend,
       _maxActivePaths = maxActivePaths,
       _trailingBlankFrames = trailingBlankFrames {
    _setKeywordsWithoutReset(keywords);
    _primeFrontend();
  }

  static const _encoderChunkFrames = 45;
  static const _encoderChunkShift = 32;

  // The streaming encoder needs acoustic history before speech begins. A live
  // microphone usually supplies this naturally, but a user can speak
  // immediately after load/setKeywords. Prime it here so the first utterance
  // is not silently lost (especially for long, rare words such as Telosnex).
  // Keep this aligned to the encoder's 320 ms chunk shift; an arbitrary
  // padding length changes feature chunk boundaries and can hurt detection.
  static const _startupPaddingSamples = 10240;
  static const _startupPadding = Duration(milliseconds: 640);

  final KwsOnnxBackend _backend;
  final int _maxActivePaths;
  final int _trailingBlankFrames;
  final EnglishKwsTokenizer _tokenizer = EnglishKwsTokenizer();
  StreamingKwsFbank _fbank = StreamingKwsFbank();
  late TransducerKeywordDecoder _decoder;
  var _processedFrames = 0;
  var _closed = false;

  Future<List<KeywordDetection>> accept(
    Float32List samples, {
    int sampleRate = 16000,
  }) async {
    _ensureOpen();
    if (sampleRate != StreamingKwsFbank.sampleRate) {
      throw ArgumentError.value(
        sampleRate,
        'sampleRate',
        'English keyword spotting currently requires 16 kHz mono audio',
      );
    }
    _fbank.accept(samples);
    return _decodeReadyChunks();
  }

  Future<List<KeywordDetection>> finish() async {
    _ensureOpen();
    // Provide enough trailing silence for blank-frame confirmation.
    _fbank.accept(Float32List(StreamingKwsFbank.sampleRate));
    _fbank.finish();
    return _decodeReadyChunks();
  }

  /// Transcribes [samples] with greedy search and no keyword graph.
  ///
  /// This reports the closest English text to what the acoustic model heard,
  /// which is the recommended way to discover [KeywordPhrase.spokenForms] for
  /// names and brands. Resets all streaming state.
  Future<KeywordTranscription> transcribe(
    Float32List samples, {
    int sampleRate = 16000,
  }) async {
    _ensureOpen();
    if (sampleRate != StreamingKwsFbank.sampleRate) {
      throw ArgumentError.value(
        sampleRate,
        'sampleRate',
        'English keyword spotting currently requires 16 kHz mono audio',
      );
    }
    await _backend.resetEncoderState();
    final fbank = StreamingKwsFbank()
      ..accept(Float32List(_startupPaddingSamples))
      ..accept(samples)
      ..accept(Float32List(StreamingKwsFbank.sampleRate ~/ 2))
      ..finish();

    final tokens = <int>[-1, TransducerKeywordDecoder.blankId];
    Float32List? decoderVectors;
    var processedFrames = 0;
    while (processedFrames + _encoderChunkFrames < fbank.numFramesReady) {
      final features = fbank.getFrames(processedFrames, _encoderChunkFrames);
      processedFrames += _encoderChunkShift;
      fbank.discardBefore(processedFrames);
      final encoder = await _backend.runEncoder(features);
      const dimension = TransducerKeywordDecoder.joinerDimension;
      for (var frame = 0; frame < encoder.frameCount; frame++) {
        decoderVectors ??= await _backend.runDecoder(
          Int64List.fromList([tokens[tokens.length - 2], tokens.last]),
        );
        final logits = await _backend.runJoiner(
          encoder.values.sublist(frame * dimension, (frame + 1) * dimension),
          decoderVectors,
        );
        var best = 0;
        for (var token = 1; token < logits.length; token++) {
          if (logits[token] > logits[best]) best = token;
        }
        if (best != TransducerKeywordDecoder.blankId &&
            best != TransducerKeywordDecoder.unknownId) {
          tokens.add(best);
          decoderVectors = null;
        }
      }
    }
    await reset();
    final tokenIds = tokens.skip(2).toList(growable: false);
    return KeywordTranscription(
      text: _tokenizer.decode(tokenIds),
      tokenizerId: keywordSpotterTokenizerId,
      tokenIds: tokenIds,
    );
  }

  Future<void> setKeywords(List<KeywordPhrase> keywords) async {
    _ensureOpen();
    _setKeywordsWithoutReset(keywords);
    await _backend.resetEncoderState();
    _fbank = StreamingKwsFbank();
    _processedFrames = 0;
    _primeFrontend();
  }

  Future<void> reset() async {
    _ensureOpen();
    _decoder.reset();
    _fbank = StreamingKwsFbank();
    _processedFrames = 0;
    _primeFrontend();
    await _backend.resetEncoderState();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _backend.close();
  }

  void _setKeywordsWithoutReset(List<KeywordPhrase> keywords) {
    keywords = validatedKeywordPhraseSnapshot(keywords);
    final tokenIds = <List<int>>[];
    final graphPhrases = <KeywordPhrase>[];
    for (final keyword in keywords) {
      for (final spokenForm in <String>[keyword.text, ...keyword.spokenForms]) {
        tokenIds.add(_tokenizer.encode(spokenForm));
        // Every pronunciation reports the user's canonical display text.
        graphPhrases.add(keyword);
      }
      for (final sequence in keyword.spokenTokenSequences) {
        tokenIds.add(sequence.tokenIds);
        graphPhrases.add(keyword);
      }
    }
    final graph = ContextGraph(tokenIds, graphPhrases);
    _decoder = TransducerKeywordDecoder(
      backend: _backend,
      graph: graph,
      maxActivePaths: _maxActivePaths,
      trailingBlankFrames: _trailingBlankFrames,
    );
  }

  Future<List<KeywordDetection>> _decodeReadyChunks() async {
    final detections = <KeywordDetection>[];
    while (_processedFrames + _encoderChunkFrames < _fbank.numFramesReady) {
      if (_decoder.trailingBlanks * 0.04 > 1.5) {
        _decoder.reset();
        await _backend.resetEncoderState();
      }
      final features = _fbank.getFrames(_processedFrames, _encoderChunkFrames);
      _processedFrames += _encoderChunkShift;
      _fbank.discardBefore(_processedFrames);
      final encoder = await _backend.runEncoder(features);
      detections.addAll(
        (await _decoder.decode(encoder)).map(_removeStartupPadding),
      );
    }
    return detections;
  }

  void _primeFrontend() {
    _fbank.accept(Float32List(_startupPaddingSamples));
  }

  static KeywordDetection _removeStartupPadding(KeywordDetection detection) =>
      KeywordDetection(
        phrase: detection.phrase,
        detectedAt: _subtractPadding(detection.detectedAt),
        tokenTimestamps: detection.tokenTimestamps
            .map(_subtractPadding)
            .toList(growable: false),
        meanTokenProbability: detection.meanTokenProbability,
      );

  static Duration _subtractPadding(Duration timestamp) {
    final adjusted = timestamp - _startupPadding;
    return adjusted.isNegative ? Duration.zero : adjusted;
  }

  void _ensureOpen() {
    if (_closed) {
      throw StateError('Keyword spotter is closed');
    }
  }
}
