/// The two Kokoro stages, independent of the ONNX runtime binding.
library;

import 'dart:typed_data';

import 'misaki/misaki_en.dart' show MisakiPs;

class KokoroTensor {
  KokoroTensor(this.data, this.shape);
  final Float32List data;
  final List<int> shape;
}

/// The prosody stage output: text features and the F0 and energy curves.
class KokoroProsody {
  KokoroProsody(this.asr, this.f0, this.energy) {
    if (asr.shape.length != 3 ||
        asr.shape[0] != 1 ||
        asr.shape[1] != 512 ||
        f0.shape.length != 2 ||
        energy.shape.length != 2 ||
        f0.shape[0] != 1 ||
        energy.shape[0] != 1 ||
        f0.shape[1] != 2 * frames ||
        energy.shape[1] != 2 * frames) {
      throw StateError('Unsupported Kokoro stage shapes');
    }
  }
  final KokoroTensor asr, f0, energy;
  int get frames => asr.shape.last;
}

/// The decoder inputs for frames [first] to [last] of [prosody].
({Float32List asr, Float32List f0, Float32List energy}) kokoroDecoderInputs(
  KokoroProsody prosody,
  int first,
  int last,
) {
  if (first < 0 || last > prosody.frames || first >= last) {
    throw RangeError('Invalid frame span');
  }
  final count = last - first;
  final asr = Float32List(512 * count);
  for (var c = 0; c < 512; c++) {
    asr.setRange(
      c * count,
      (c + 1) * count,
      prosody.asr.data,
      c * prosody.frames + first,
    );
  }
  return (
    asr: asr,
    f0: Float32List.sublistView(prosody.f0.data, 2 * first, 2 * last),
    energy: Float32List.sublistView(prosody.energy.data, 2 * first, 2 * last),
  );
}

/// Validates the prosody stage request.
void kokoroCheckProsodyRequest(List<int> ids, double speed) {
  if (ids.isEmpty || ids.length > 510 || !speed.isFinite || speed <= 0) {
    throw ArgumentError('Invalid phoneme count or speed');
  }
}

/// The model sessions of one Kokoro engine: native FFI or ORT Web.
abstract interface class KokoroStages {
  Future<KokoroProsody> prosody(List<int> ids, Float32List style, double speed);

  /// Returns 600 samples per frame of [first] to [last].
  Future<Float32List> decode(
    KokoroProsody prosody,
    Float32List style,
    int first,
    int last,
  );

  /// misaki's out-of-vocabulary model, for one word.
  Future<MisakiPs> fallback(String word);

  Future<void> close();
}
