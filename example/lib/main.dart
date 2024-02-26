import 'package:flutter/material.dart';
import 'package:fonnx_example/magika_widget.dart';
import 'package:fonnx_example/minilml6v2_widget.dart';
import 'package:fonnx_example/msmarco_minilm_l6v3_widget.dart';
import 'package:fonnx_example/silero_vad_widget.dart';
import 'package:fonnx_example/tts_demo_widget.dart';
import 'package:fonnx_example/whisper_widget.dart';
import 'package:libmonet/libmonet.dart';
import 'package:libmonet/theming/monet_theme_data.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final brightness =
        MediaQuery.maybePlatformBrightnessOf(context) ?? Brightness.dark;
    final surfaceLstar = brightness == Brightness.dark ? 10.0 : 93.0;

    return MaterialApp(
      home: MonetTheme(
        monetThemeData: MonetThemeData.fromColor(
          color: const Color(0xffF93081),
          brightness: brightness,
          backgroundTone: surfaceLstar,
        ),
        child: Builder(builder: (context) {
          final appBar = AppBar(
            title: Text(
              'FONNX',
              style:
                  Theme.of(context).textTheme.headlineLarge!.copyWith(shadows: [
                Shadow(
                    color: MonetTheme.of(context).primary.background,
                    offset: const Offset(0, 0),
                    blurRadius: 4),
                Shadow(
                    color: MonetTheme.of(context).primary.background,
                    offset: const Offset(0, 0),
                    blurRadius: 4),
                Shadow(
                    color: MonetTheme.of(context).primary.background,
                    offset: const Offset(0, 0),
                    blurRadius: 4),
              ]),
            ),
            backgroundColor: Colors.transparent,
          );
          return Scaffold(
            extendBodyBehindAppBar: true,
            appBar: appBar,
            body: SingleChildScrollView(
              padding: EdgeInsets.only(top: appBar.preferredSize.height),
              child: const Padding(
                padding: EdgeInsets.only(left: 16, right: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TtsDemoWidget(),
                    SizedBox(height: 16),
                    MagikaWidget(),
                    SizedBox(height: 16),
                    SileroVadWidget(),
                    SizedBox(height: 16),
                    MiniLmL6V2Widget(),
                    SizedBox(height: 16),
                    MsmarcoMiniLmL6V3Widget(),
                    SizedBox(height: 16),
                    WhisperWidget(),
                    SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          );
        }
        ),
      ),
    );
  }
}
