import 'package:flutter_test/flutter_test.dart';

import 'package:budget_tracker/main.dart';

void main() {
  testWidgets('BudgetApp renders', (WidgetTester tester) async {
    await tester.pumpWidget(const BudgetApp());
    expect(find.byType(BudgetApp), findsOneWidget);
  });
}
