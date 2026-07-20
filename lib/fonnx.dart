/// FONNX model APIs.
///
/// Native inference is implemented once in Dart FFI and backed by native code
/// assets. Web model implementations remain selected by each model library's
/// conditional import.
library;

export 'extensions/vector.dart';
export 'models/magika/magika.dart';
export 'models/pyannote/pyannote.dart';
export 'models/whisper/whisper.dart';
