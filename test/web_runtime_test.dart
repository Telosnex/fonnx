@TestOn('browser')
@Timeout(Duration(minutes: 10))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fonnx/fonnx.dart';
import 'package:fonnx/models/minilml6v2/mini_lm_l6_v2.dart';
import 'package:fonnx/models/minishLab/minish_lab.dart';
import 'package:fonnx/models/msmarcoMiniLmL6V3/msmarco_mini_lm_l6_v3.dart';
import 'package:fonnx/models/sileroVad/silero_vad.dart';
import 'package:fonnx/src/web_loader.dart';
import 'package:fonnx/src/web_runtime.g.dart';

/// Runs every FONNX web model through its public API in the browser, on the
/// web runtime files in lib/web/ (native_prebuilt ADR 002 D13). Install the
/// generated files first: `dart run native_prebuilt:web install-dev`.
///
/// The test server serves test/ at the root, so the models come from the
/// test/web_models link to example/assets/models (hydrate Git LFS first).
void main() {
  setUpAll(() => FonnxWeb.runtimeUri = Uri.parse('packages/fonnx/web/'));

  test('the URL of each runtime file has the webVersion query', () {
    expect(
      fonnxWebModuleUrl(
        'whisper_init.js',
        baseUri: 'https://a.b/app/x.html',
      ).toString(),
      'https://a.b/app/packages/fonnx/web/whisper_init.js?v=$webRuntimeVersion',
    );
  });

  test('Magika', () async {
    final type = await Magika.load(
      'web_models/magika/magika.onnx',
    ).getType(await _bytes('data/magika/basic/code.c'));
    expect(type, MagikaType.c);
  });

  test('Whisper', () async {
    final transcript = await Whisper.load(
      'web_models/whisper/whisper_tiny.onnx',
    ).doInference(await _bytes('data/audio_sample_ac1_ar16000.pcm'));
    expect(transcript.trim(), 'The rain and Spain falls mainly on the plane.');
  });

  test('Silero VAD', () async {
    final golden =
        jsonDecode(
              utf8.decode(
                await _bytes('data/goldens/silero_vad_rain_in_spain.json'),
              ),
            )
            as Map<String, dynamic>;
    final input = (golden['input'] as String).replaceFirst('test/', '');
    final expected = (golden['output'] as List).cast<num>();
    final result = await SileroVad.load(
      'web_models/sileroVad/silero_vad_v6.2.1.onnx',
    ).doInference(await _bytes(input));
    final output = result['output'] as Float32List;
    expect(output, hasLength(expected.length));
    for (var i = 0; i < expected.length; i++) {
      expect(output[i], closeTo(expected[i], 1e-4), reason: 'frame $i');
    }
  });

  test('Pyannote', () async {
    final segments =
        await Pyannote.load('web_models/pyannote/pyannote_seg3.onnx').process(
          Pyannote.int16PcmBytesToFloat32(
            await _bytes('data/audio_sample_ac1_ar16000.pcm'),
          ),
        );
    expect(segments, isNotEmpty);
    for (final segment in segments) {
      expect(
        segment['stop'] as double,
        greaterThan(segment['start'] as double),
      );
    }
  });

  test('MiniLM L6 V2 and MSMARCO MiniLM L6 V3', () async {
    final tokens = MiniLmL6V2.tokenizer.tokenize('Hello').first.tokens;
    final miniLm = await MiniLmL6V2.load(
      'web_models/miniLmL6V2/miniLmL6V2.onnx',
    ).getEmbeddingAsVector(tokens);
    expect(miniLm, hasLength(384));
    expect(miniLm.every((v) => v.isFinite), isTrue);
    final msmarco = await MsmarcoMiniLmL6V3.load(
      'web_models/msmarcoMiniLmL6V3/msmarcoMiniLmL6V3.onnx',
    ).getEmbeddingAsVector(tokens);
    expect(msmarco, hasLength(384));
  });

  test('MinishLab potion8m', () async {
    final embedding = await MinishLab.load('web_models/minishLab/potion8m.onnx')
        .getEmbeddingAsVector(
          MinishLab.potion8mTokenizer.tokenize('Hello').first.tokens,
        );
    expect(embedding, hasLength(256));
    expect(embedding.norm(), closeTo(1, 1e-5));
  });

  test('Keyword spotter', () async {
    final spotter = await KeywordSpotter.load(
      bundle: KeywordSpotterBundle.gigaSpeech3m('web_models/keywordSpotter'),
      keywords: const [KeywordPhrase('rain in Spain')],
    );
    final detections = <KeywordDetection>[];
    final subscription = spotter.detections.listen(detections.add);
    try {
      final pcm = await _bytes('data/audio_sample_ac1_ar16000.pcm');
      const chunk = 3200;
      for (var offset = 0; offset < pcm.length; offset += chunk) {
        final end = offset + chunk < pcm.length ? offset + chunk : pcm.length;
        await spotter.acceptPcm16(pcm.sublist(offset, end));
      }
      await spotter.finish();
      expect(detections.map((d) => d.phrase), ['rain in Spain']);
    } finally {
      await subscription.cancel();
      await spotter.close();
    }
  });

  test('FUTO Swipe', () async {
    final swipe = await FutoSwipe.load(
      bundle: FutoSwipeBundle.fromDirectory('web_models/futoSwipe'),
    );
    try {
      expect(swipe.lexiconSize, greaterThan(1000));
      final predicted = await swipe.predictNextWords(const [
        'I',
        'went',
        'to',
        'the',
      ], count: 5);
      expect(predicted, hasLength(5));
    } finally {
      await swipe.close();
    }
  });

  // ADR 002 D7, I3. The Worker reports the files that it loaded.
  test('a model Worker loads ORT and its Wasm with the query', () async {
    final worker = _Worker(
      fonnxWebModuleUrl('magika_worker.js').toString().toJS,
      _WorkerOptions(type: 'module'),
    );
    try {
      final model = (await _bytes('web_models/magika/magika.onnx')).buffer.toJS;
      await _request(worker, 'loadModel', {'modelArrayBuffer': model});
      final urls = [
        for (final url
            in ((await _request(worker, 'resourceUrls', {}))['urls']!
                    as JSArray<JSString>)
                .toDart)
          Uri.parse(url.toDart),
      ];
      final loaded = urls.where((u) => u.path.contains('/packages/fonnx/web/'));
      expect(loaded.map((u) => u.pathSegments.last).toSet(), {
        'ort.min.mjs',
        'ort-wasm-simd-threaded.mjs',
        'ort-wasm-simd-threaded.wasm',
      });
      for (final url in loaded) {
        expect(url.queryParameters['v'], webRuntimeVersion, reason: '$url');
      }
    } finally {
      worker.terminate();
    }
  });
}

Future<Uint8List> _bytes(String path) async {
  final response = await _fetch(path.toJS).toDart;
  if (!response.ok) fail('GET $path: HTTP ${response.status}');
  return (await response.arrayBuffer().toDart).toDart.asUint8List();
}

var _nextId = 0;

Future<Map<String, JSAny?>> _request(
  _Worker worker,
  String action,
  Map<String, JSAny?> payload,
) {
  final id = 'test-${_nextId++}';
  final completer = Completer<Map<String, JSAny?>>();
  worker.onmessage = ((_MessageEvent event) {
    final data = event.data.dartify()! as Map;
    if (data['messageId'] != id || completer.isCompleted) return;
    if (data['action'] == 'error') {
      completer.completeError(StateError('${data['error']}'));
    } else {
      completer.complete({
        for (final key in data.keys)
          '$key': (event.data! as JSObject).getProperty('$key'.toJS),
      });
    }
  }).toJS;
  final message = JSObject()
    ..setProperty('protocolVersion'.toJS, 1.toJS)
    ..setProperty('action'.toJS, action.toJS)
    ..setProperty('messageId'.toJS, id.toJS);
  for (final MapEntry(:key, :value) in payload.entries) {
    message.setProperty(key.toJS, value);
  }
  worker.postMessage(message);
  return completer.future.timeout(const Duration(minutes: 2));
}

@JS('fetch')
external JSPromise<_Response> _fetch(JSString url);

extension type _Response._(JSObject _) implements JSObject {
  external bool get ok;
  external int get status;
  external JSPromise<JSArrayBuffer> arrayBuffer();
}

extension type _WorkerOptions._(JSObject _) implements JSObject {
  external factory _WorkerOptions({String type});
}

extension type _MessageEvent._(JSObject _) implements JSObject {
  external JSAny? get data;
}

@JS('Worker')
extension type _Worker._(JSObject _) implements JSObject {
  external factory _Worker(JSString url, _WorkerOptions options);
  external void postMessage(JSAny? message);
  external void terminate();
  external set onmessage(JSFunction? handler);
}
