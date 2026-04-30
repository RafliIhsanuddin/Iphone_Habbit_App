import 'package:flutter_test/flutter_test.dart';

import 'package:habit_app/main.dart';

void main() {
  testWidgets('Habit app smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const HabitApp());

    // Verify that the HABITS title appears
    expect(find.text('HABITS'), findsOneWidget);

    // Verify that the NO HABITS YET text appears
    expect(find.text('NO HABITS YET'), findsOneWidget);
  });
}