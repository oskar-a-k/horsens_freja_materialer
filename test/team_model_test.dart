import 'package:flutter_test/flutter_test.dart';
import 'package:horsens_freja_materialer_web/models/team_model.dart';

void main() {
  test('TeamModel serializes kit sets', () {
    final team = TeamModel(
      id: 'team-1',
      name: 'U14',
      kitSets: [
        TeamKitSetModel(
          id: 'set-1',
          setNumber: '8',
          jerseyColor: 'hvid',
          jerseySize: 'M',
          jerseyStatus: 'ok',
          shortsColor: 'rød',
          shortsSize: 'M',
          shortsStatus: 'ok',
          socksColor: 'rød',
          socksSize: '38-41',
          socksStatus: 'skal udskiftes',
          duffelbagColor: 'orange',
          duffelbagStatus: 'ok',
          note: 'Eksempel',
        ),
      ],
    );

    final encoded = team.toMap();
    final decoded = TeamModel.fromMap('team-1', encoded);

    expect(decoded.kitSets, hasLength(1));
    expect(decoded.kitSets.first.setNumber, '8');
    expect(decoded.kitSets.first.jerseyColor, 'hvid');
    expect(decoded.kitSets.first.jerseySize, 'M');
    expect(decoded.kitSets.first.shortsColor, 'rød');
    expect(decoded.kitSets.first.socksStatus, 'skal udskiftes');
    expect(decoded.kitSets.first.socksColor, 'rød');
    expect(decoded.kitSets.first.duffelbagColor, 'orange');
    expect(decoded.kitSets.first.duffelbagStatus, 'ok');
    expect(decoded.kitSets.first.note, 'Eksempel');
  });

  test('team material helpers use one consistent quantity source', () {
    final team = TeamModel(
      id: 'team-2',
      name: 'Herre hold 3',
      holdings: {'sportstape-wide': 1},
      expectedHoldings: {'sportstape-wide': 1},
    );

    expect(teamActualMaterialCount(team, 'sportstape-wide'), 1);
    expect(teamExpectedMaterialCount(team, 'sportstape-wide'), 1);
    expect(teamMissingMaterialCount(team, 'sportstape-wide'), 0);

    final downgraded = team.copyWith(holdings: {'sportstape-wide': 0});

    expect(teamActualMaterialCount(downgraded, 'sportstape-wide'), 0);
    expect(teamMissingMaterialCount(downgraded, 'sportstape-wide'), 1);

    final raw = team.toMap();
    expect(teamActualMaterialCountFromMap(raw, 'sportstape-wide'), 1);
    expect(teamExpectedMaterialCountFromMap(raw, 'sportstape-wide'), 1);
    expect(teamMissingMaterialCountFromMap(raw, 'sportstape-wide'), 0);
  });
}
