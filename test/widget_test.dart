// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:horsens_freja_materialer_web/models/team_model.dart';

void main() {
  test('Teams are ordered by custom sort order', () {
    final teams = [
      TeamModel(id: '2', name: 'Zeta', sortOrder: 0),
      TeamModel(id: '1', name: 'Alpha', sortOrder: 1),
      TeamModel(id: '3', name: 'Beta', sortOrder: 0),
    ];

    final sorted = sortTeamsForDisplay(teams);

    expect(sorted.map((team) => team.id).toList(), ['3', '2', '1']);
  });
}
