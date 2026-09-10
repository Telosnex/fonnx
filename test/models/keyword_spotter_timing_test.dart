import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fonnx/models/keyword_spotter/keyword_spotter.dart';
import 'package:fonnx/models/keyword_spotter/src/context_graph.dart';
import 'package:fonnx/models/keyword_spotter/src/keyword_spotter_engine.dart';
import 'package:fonnx/models/keyword_spotter/src/transducer_decoder.dart';

void main() {
  test('confirmation time is not the final token time', () async {
    final backend = _ScriptedBackend(tokenFrames: {0});
    final decoder = _decoder(backend);
    final detection = (await decoder.decode(_encoder(4))).single;

    expect(detection.startTime, Duration.zero);
    expect(detection.endTime, const Duration(milliseconds: 40));
    expect(detection.detectedAt, const Duration(milliseconds: 80));
  });

  test('silence reset preserves the clock; public reset restarts it', () async {
    final backend = _ScriptedBackend(tokenFrames: {64, 68});
    final decoder = _decoder(backend);
    await decoder.decode(_encoder(64));
    decoder.reset(preserveTimeline: true);
    final first = (await decoder.decode(_encoder(4))).single;
    expect(first.startTime, const Duration(milliseconds: 2560));
    expect(first.detectedAt, const Duration(milliseconds: 2640));

    decoder.reset();
    final second = (await decoder.decode(_encoder(4))).single;
    expect(second.startTime, Duration.zero);
    expect(second.detectedAt, const Duration(milliseconds: 80));
  });

  test(
    'engine timestamps survive repeated blank resets and startup padding',
    () async {
      final backend = _ScriptedBackend(tokenFrames: {100});
      final engine = KeywordSpotterEngine(
        backend: backend,
        maxActivePaths: 1,
        keywords: const [
          KeywordPhrase(
            'a',
            spokenTokenSequences: [
              KeywordTokenSequence(
                tokenizerId: keywordSpotterTokenizerId,
                tokenIds: [3],
              ),
            ],
          ),
        ],
      );
      final detections = await engine.accept(Float32List(16000 * 6));
      expect(backend.resets, greaterThan(1));
      final detection = detections.single;
      // 100 * 40ms, minus the one 640ms frontend prefix. Silence resets
      // must not turn this into a position near the start of the recording.
      expect(detection.startTime, const Duration(milliseconds: 3360));
      expect(detection.endTime, const Duration(milliseconds: 3400));
      expect(detection.detectedAt, const Duration(milliseconds: 3440));
      await engine.close();
    },
  );
}

TransducerKeywordDecoder _decoder(_ScriptedBackend backend) =>
    TransducerKeywordDecoder(
      backend: backend,
      maxActivePaths: 1,
      graph: ContextGraph(
        const [
          [3],
        ],
        const [KeywordPhrase('wake')],
      ),
    );

KwsEncoderOutput _encoder(int frames) => KwsEncoderOutput(
  values: Float32List(frames * TransducerKeywordDecoder.joinerDimension),
  frameCount: frames,
);

class _ScriptedBackend implements KwsOnnxBackend {
  final Set<int> tokenFrames;
  int frame = 0;
  int resets = 0;
  _ScriptedBackend({required this.tokenFrames});

  @override
  Future<KwsEncoderOutput> runEncoder(Float32List features) async =>
      _encoder(8);

  @override
  Future<Float32List> runDecoder(Int64List tokenContexts) async =>
      Float32List(TransducerKeywordDecoder.joinerDimension);

  @override
  Future<Float32List> runJoiner(
    Float32List encoderVectors,
    Float32List decoderVectors,
  ) async {
    final logits = Float32List(TransducerKeywordDecoder.vocabSize)
      ..fillRange(0, TransducerKeywordDecoder.vocabSize, -100);
    logits[tokenFrames.contains(frame++) ? 3 : 0] = 100;
    return logits;
  }

  @override
  Future<void> resetEncoderState() async {
    resets++;
  }

  @override
  Future<void> close() async {}
}
