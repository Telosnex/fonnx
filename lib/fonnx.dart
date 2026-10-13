/// FONNX model APIs.
///
/// Native inference is implemented once in Dart FFI and backed by native code
/// assets. Web model implementations remain selected by each model library's
/// conditional import. On the web, each model loads its runtime files from
/// [FonnxWeb.runtimeUri] at first use.
library;

export 'extensions/vector.dart';
export 'models/futo_swipe/futo_swipe.dart';
export 'models/keyword_spotter/keyword_spotter.dart';
export 'models/magika/magika.dart';
export 'models/pyannote/pyannote.dart';
export 'models/whisper/whisper.dart';
export 'src/web_config.dart';
