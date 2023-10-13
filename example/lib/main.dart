import 'package:flutter/material.dart';
import 'package:fonnx_example/minilml6v2_widget.dart';
import 'package:fonnx_example/msmarco_minilm_l6v3_widget.dart';

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
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Fonnx Example App'),
        ),
        body: const SingleChildScrollView(
          child: Column(
            children: [
              MiniLmL6V2Widget(),
              MsmarcoMiniLmL6V3Widget(),
            ],
          ),
        ),
      ),
    );
  }
}
