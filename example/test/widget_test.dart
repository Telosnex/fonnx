import 'package:flutter_test/flutter_test.dart';
import 'package:fonnx_example/main.dart';

void main() {
  testWidgets('renders demos without ad-hoc correctness controls',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('FONNX'), findsOneWidget);
    expect(find.text('Test Correctness'), findsNothing);
    expect(find.text('Test Speed'), findsNWidgets(6));
  });
}
