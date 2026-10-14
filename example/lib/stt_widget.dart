import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fonnx_example/padding.dart';
import 'package:fonnx_example/stt_models.dart';

/// Speech recognition: transcribes a bundled clip with the chosen model and
/// shows the speed.
class SttWidget extends StatefulWidget {
  const SttWidget({super.key});

  @override
  State<SttWidget> createState() => _SttWidgetState();
}

class _SttWidgetState extends State<SttWidget> {
  var _model = SttModel.fastConformer;
  bool _running = false;
  String? _status;
  String? _transcript;
  String? _speed;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        heightPadding,
        Text(
          'Speech Recognition',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        heightPadding,
        SttModelPicker(
          value: _model,
          onChanged: _running
              ? null
              : (model) => setState(() {
                  _model = model;
                  _transcript = null;
                  _speed = null;
                  _status = null;
                }),
        ),
        heightPadding,
        Row(
          children: [
            ElevatedButton(
              onPressed: _running ? null : _runPerformanceTest,
              child: const Text('Test Speed'),
            ),
            widthPadding,
            if (_status != null)
              Flexible(child: Text(_status!))
            else if (_speed != null)
              Text('${_speed}x realtime'),
          ],
        ),
        if (_transcript != null) ...[heightPadding, Text('"$_transcript"')],
      ],
    );
  }

  void _runPerformanceTest() async {
    final model = _model;
    setState(() {
      _running = true;
      _status = model.downloads ? 'Getting model…' : 'Loading model…';
    });
    try {
      final inference = await model.load(
        onProgress: (received, total) {
          if (total == null || total == 0) return;
          setState(
            () => _status =
                'Downloading model: ${(100 * received / total).floor()}%',
          );
        },
      );
      setState(() => _status = 'Transcribing…');
      final (transcript, speed) = await testSttPerformance(inference, model);
      setState(() {
        _transcript = transcript;
        _speed = speed;
        _status = null;
      });
    } catch (e) {
      debugPrint('${model.label} failed: $e');
      setState(() => _status = 'Error: $e');
    } finally {
      setState(() => _running = false);
    }
  }
}

/// Chooses a [SttModel], and shows its description.
class SttModelPicker extends StatelessWidget {
  const SttModelPicker({super.key, required this.value, this.onChanged});

  final SttModel value;

  /// Null disables the picker.
  final ValueChanged<SttModel>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButton<SttModel>(
          value: value,
          onChanged: onChanged == null
              ? null
              : (model) {
                  if (model != null) onChanged!(model);
                },
          items: [
            for (final model in SttModel.values)
              DropdownMenuItem(value: model, child: Text(model.label)),
          ],
        ),
        Text(
          value.downloads
              ? '${value.description} The first use downloads the model.'
              : value.description,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// Returns the transcript of the bundled clip and the speed as a multiple of
/// realtime.
Future<(String, String)> testSttPerformance(
  SttInference inference,
  SttModel model,
) async {
  // "The rain in Spain falls mainly on the plain": 16-bit PCM, mono, 16 kHz.
  final pcm = await rootBundle.load('assets/audio_sample_ac1_ar16000.pcm');
  final bytes = pcm.buffer.asUint8List(pcm.offsetInBytes, pcm.lengthInBytes);
  final audioMs = bytes.length / 2 / 16000 * 1000;

  // The first run includes loading the model, so it is not timed.
  const iterations = 3;
  var transcript = '';
  final sw = Stopwatch();
  for (var i = 0; i < iterations; i++) {
    if (i == 1) sw.start();
    transcript = await inference(bytes);
  }
  sw.stop();
  final average = sw.elapsedMilliseconds / (iterations - 1);
  final speed = audioMs / average;
  debugPrint('${model.label} performance:');
  debugPrint('  Average: ${average.toStringAsFixed(0)} ms');
  debugPrint('  Speed multiplier: ${speed.toStringAsFixed(2)}x');
  debugPrint('  Transcript: $transcript');
  return (transcript.trim(), speed.toStringAsFixed(2));
}
