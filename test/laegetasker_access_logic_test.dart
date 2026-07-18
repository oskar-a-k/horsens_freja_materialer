import 'package:flutter_test/flutter_test.dart';
import 'package:horsens_freja_materialer_web/models/team_model.dart';
import 'package:horsens_freja_materialer_web/services/laegetasker_access_logic.dart';

void main() {
  final teams = [
    TeamModel(id: 'u15', name: 'U15'),
    TeamModel(id: 'u16', name: 'U16'),
    TeamModel(id: 'u17', name: 'U17'),
  ];

  group('LaegetaskerAccessLogic.shouldLockTeams', () {
    test('does not lock admins even when they have an assigned team', () {
      final shouldLock = LaegetaskerAccessLogic.shouldLockTeams(
        isAdmin: true,
        assignedTeam: teams[1],
      );

      expect(shouldLock, isFalse);
    });

    test('locks non-admins when they have an assigned team', () {
      final shouldLock = LaegetaskerAccessLogic.shouldLockTeams(
        isAdmin: false,
        assignedTeam: teams[1],
      );

      expect(shouldLock, isTrue);
    });
  });

  group('LaegetaskerAccessLogic.visibleTeams', () {
    test('shows all teams for admin-like unlocked state', () {
      final visible = LaegetaskerAccessLogic.visibleTeams(
        teams: teams,
        teamLocked: false,
        assignedTeam: teams[1],
      );

      expect(visible.map((team) => team.id), ['u15', 'u16', 'u17']);
    });

    test('shows only assigned team for locked coach state', () {
      final visible = LaegetaskerAccessLogic.visibleTeams(
        teams: teams,
        teamLocked: true,
        assignedTeam: teams[1],
      );

      expect(visible.map((team) => team.id), ['u16']);
    });

    test('shows all teams when no assigned team exists', () {
      final visible = LaegetaskerAccessLogic.visibleTeams(
        teams: teams,
        teamLocked: false,
        assignedTeam: null,
      );

      expect(visible.map((team) => team.id), ['u15', 'u16', 'u17']);
    });
  });
}
