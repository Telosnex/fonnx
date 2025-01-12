import 'package:ml_linalg/distance.dart';
import 'package:ml_linalg/vector.dart';

extension Similarity on Vector {
  double cosineSimilarity(Vector vector) {
    if (length != vector.length) {
      print('Fonnx.Vector.Similarity.cosineSimilarity: Vectors must have the same length. A vector has length $length, while the other has length ${vector.length}. Returning 0 for similarity.');
      return 0.0;
    }
    final distance = distanceTo(vector, distance: Distance.cosine);
    return 1.0 - distance;
  }
}

extension Average on Iterable<Vector> {
  Vector? get normalizedAverage {
    if (isEmpty) {
      return null;
    }

    final length = this.length;
    final sum = fold(Vector.zero(first.length), (previousValue, element) {
      return previousValue + element;
    });

    final average = sum / length;
    return average.normalize();
  }
}
