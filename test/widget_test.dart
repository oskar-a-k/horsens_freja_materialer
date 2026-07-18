// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:horsens_freja_materialer_web/main.dart';
import 'package:horsens_freja_materialer_web/services/inventory_service.dart';

void main() {
  testWidgets('Home page loads', (WidgetTester tester) async {
    await tester.pumpWidget(
      MyApp(inventoryService: InMemoryInventoryService()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Materialforvalter'), findsOneWidget);
    expect(find.text('Hold'), findsOneWidget);
    expect(find.text('Lager'), findsOneWidget);
  });
}
