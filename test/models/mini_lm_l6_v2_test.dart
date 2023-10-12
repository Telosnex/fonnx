import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ml_linalg/linalg.dart';

import 'package:fonnx/models/minilml6v2/mini_lm_l6_v2_native.dart';

extension Similarity on Vector {
  double similarity(Vector vector) {
    final distance = distanceTo(vector, distance: Distance.cosine);
    return 1.0 - distance;
  }
}

void main() {
  const modelPath = 'models/miniLmL6V2/miniLmL6V2.onnx';
  final miniLmL6V2 = MiniLmL6V2Native(modelPath);

  Future<Vector> vec(String text) async {
    return (await miniLmL6V2.getEmbedding(text)).first.embedding;
  }

  test('Embedding works', () async {
    final answer = await vec('');
    expect(answer, hasLength(384));
  });

  test('Normalize works', () async {
    final result = await miniLmL6V2.truncateAndGetEmbeddingForString('');
    expect(result.embedding, hasLength(384));
  });

  test('Performance test', () async {
    const count = 1000;
    final List<String> randomStrings = [];
    final random = Random();
    for (var i = 0; i < count; i++) {
      final randomString256Chars = List.generate(256, (index) {
        final trulyRandomLetter = String.fromCharCode(random.nextInt(26) + 97);
        return trulyRandomLetter;
      }).join();
      randomStrings.add(randomString256Chars);
    }

    List<Future> futures = [];
    for (var i = 0; i < count; i++) {
      final future = miniLmL6V2.getEmbedding(randomStrings[i]);
      futures.add(future);
    }
    final sw = Stopwatch()..start();
    await Future.wait(futures);
    sw.stop();
    final elapsed = sw.elapsedMilliseconds;
    debugPrint(
        'Elapsed: $elapsed ms for $count embeddings (${elapsed / count} ms per embedding)');
  });

  test('Similarity', () async {
    final result1 = await miniLmL6V2.truncateAndGetEmbeddingForString('Bonjour');
    final result2 = await miniLmL6V2.truncateAndGetEmbeddingForString('Ni hao');
    final result = result1.embedding.similarity(result2.embedding);
    expect(result, closeTo(0.261, 0.001));
  });

  test('Similarity: weather', () async {
    final vSF =
        (await miniLmL6V2.truncateAndGetEmbeddingForString('shipping forecast'))
            .embedding;
    final vAnswer =
        await vec('WeatherChannel Spain the weather is sunny and warm');
    final vWF = await vec('weather forecast');
    final vSpainWF = await vec('spain weather forecast');
    final vWFInSpain = await vec('weather forecast in Spain');
    final vBuffaloWeatherForecast = await vec('buffalo weather forecast');

    final sSFToAnswer = vSF.similarity(vAnswer);
    final sWFToAnswer = vWF.similarity(vAnswer);
    final sSpainWFToAnswer = vSpainWF.similarity(vAnswer);
    final sWFInSpainToAnswer = vWFInSpain.similarity(vAnswer);
    final sWFInBuffaloToAnswer = vBuffaloWeatherForecast.similarity(vAnswer);

    expect(sSFToAnswer, closeTo(0.189, 0.001));
    expect(sWFInBuffaloToAnswer, closeTo(0.278, 0.001));
    expect(sWFToAnswer, closeTo(0.470, 0.001));
    expect(sSpainWFToAnswer, closeTo(0.730, 0.001));
    expect(sWFInSpainToAnswer, closeTo(0.744, 0.001));
  });

  test('Similarity: password', () async {
    final vQuery = await vec('whats my jewelry pin');
    final vAnswer = await vec('My safe passcode is 1234');
    expect(vQuery.similarity(vAnswer), closeTo(0.386, 0.001));
    final vRandom = await vec('Rain in Spain falls mainly on the plain');
    expect(vQuery.similarity(vRandom), closeTo(0.008, 0.001));
  });
}
