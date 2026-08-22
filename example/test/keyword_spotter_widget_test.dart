import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fonnx_example/keyword_spotter_widget.dart';

void main() {
  testWidgets(
    'correctness passes for runtime changes and Telosnex alias',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: KeywordSpotterWidget()),
          ),
        ),
      );

      await tester.runAsync(() async {
        await tester.tap(find.text('Test Correctness'));
        // Real ONNX inference across three decoding passes; poll for result.
        for (var i = 0; i < 600; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pump();
          final passed = find.byIcon(Icons.check).evaluate().isNotEmpty;
          final failed = find.byIcon(Icons.close).evaluate().isNotEmpty;
          if (passed || failed) break;
        }
      });

      await tester.pump();
      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(find.byIcon(Icons.close), findsNothing);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
