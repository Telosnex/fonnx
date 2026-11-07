# fonnx examples

The example app in this directory runs every model. These are the two
basic steps.

## Download a model

The model files are on Hugging Face, not in the package. The catalog pins
each file's URL, size and SHA-256, and the helper checks the file before it
is used:

```dart
import 'package:fonnx/runtime_models.dart';

final model = await ensureFonnxRuntimeModel(
  'pyannote/pyannote_seg3.onnx',
  modelDirectory,
);
```

## Spot keywords in a microphone stream

```dart
final spotter = await KeywordSpotter.load(
  bundle: KeywordSpotterBundle.gigaSpeech3m(modelDirectory),
  keywords: const [
    KeywordPhrase('telosnex', spokenForms: ['tell us next']),
  ],
);
spotter.detections.listen((event) => print(event.phrase));
await spotter.acceptPcm16(microphoneBytes);
await spotter.close();
```

See the package README for embeddings, Whisper, Kokoro, FUTO Swipe and the
other models.
