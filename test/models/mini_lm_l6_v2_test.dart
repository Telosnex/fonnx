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

  test('Embedding works', () async {
    final answer = await miniLmL6V2.getEmbedding('');
    expect(answer, hasLength(384));
  });

  test('Normalize works', () async {
    final embedding = await miniLmL6V2.getEmbedding('');
    final vector = Vector.fromList(embedding);
    final normalized = vector.normalize();
    expect(normalized, hasLength(384));
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
    final vector1 = Vector.fromList(
      await miniLmL6V2.getEmbedding('Hello world'),
    ).normalize();
    final vector2 = Vector.fromList(
      await miniLmL6V2.getEmbedding('Ni hao'),
    ).normalize();
    final result = vector1.similarity(vector2);
    expect(result, closeTo(0.521, 0.001));
  });

  test('Similarity: weather', () async {
    final vSF = Vector.fromList(
      await miniLmL6V2.getEmbedding('shipping forecast'),
    ).normalize();
    final vAnswer = Vector.fromList(
      await miniLmL6V2
          .getEmbedding('WeatherChannel Spain the weather is sunny and warm'),
    ).normalize();
    final vWF = Vector.fromList(
      await miniLmL6V2.getEmbedding('weather forecast'),
    ).normalize();
    final vSpainWF = Vector.fromList(
      await miniLmL6V2.getEmbedding('spain weather forecast'),
    ).normalize();
    final vWFInSpain = Vector.fromList(
      await miniLmL6V2.getEmbedding('weather forecast in Spain'),
    ).normalize();
    final vBuffaloWeatherForecast = Vector.fromList(
      await miniLmL6V2.getEmbedding('buffalo weather forecast'),
    ).normalize();

    final sSFToAnswer = vSF.similarity(vAnswer);
    final sWFToAnswer = vWF.similarity(vAnswer);
    final sSpainWFToAnswer = vSpainWF.similarity(vAnswer);
    final sWFInSpainToAnswer = vWFInSpain.similarity(vAnswer);
    final sWFInBuffaloToAnswer = vBuffaloWeatherForecast.similarity(vAnswer);

    expect(sSFToAnswer, closeTo(0.114, 0.001));
    expect(sWFInBuffaloToAnswer, closeTo(0.210, 0.001));
    expect(sSpainWFToAnswer, closeTo(0.275, 0.001));
    expect(sWFToAnswer, closeTo(0.448, 0.001));
    expect(sWFInSpainToAnswer, closeTo(0.635, 0.001));
  });

  test('Similarity: password', () async {
    final vQuery =
        Vector.fromList(await miniLmL6V2.getEmbedding('whats my jewelry pin'));
    final vAnswer = Vector.fromList(
        await miniLmL6V2.getEmbedding('My safe passcode is 1234'));
    expect(vQuery.similarity(vAnswer), closeTo(0.361, 0.001));
    final vRandom = Vector.fromList(await miniLmL6V2
        .getEmbedding('Rain in Spain falls mainly on the plain'));
    expect(vQuery.similarity(vRandom), closeTo(0.125, 0.001));
  });
}
