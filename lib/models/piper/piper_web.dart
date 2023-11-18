import 'package:fonnx/models/piper/piper.dart';

Piper getPiper(String path) => PiperWeb(path);

class PiperWeb implements Piper {
  final String modelPath;

  PiperWeb(this.modelPath);
}
