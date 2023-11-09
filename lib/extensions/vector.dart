import 'package:ml_linalg/distance.dart';
import 'package:ml_linalg/vector.dart';

extension Similarity on Vector {
  double cosineSimilarity(Vector vector) {
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
    final sum =
        fold(Vector.zero(first.length), (previousValue, element) {
      return previousValue + element;
    });

    final average = sum / length;
    return average.normalize();
  }
}
