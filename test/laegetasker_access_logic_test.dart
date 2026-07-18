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
    test('does not lock admins even when they have assigned teams', () {
      final shouldLock = LaegetaskerAccessLogic.shouldLockTeams(
        isAdmin: true,
        assignedTeams: [teams[1], teams[2]],
      );

      expect(shouldLock, isFalse);
    });

    test('locks non-admins when they have assigned teams', () {
      final shouldLock = LaegetaskerAccessLogic.shouldLockTeams(
        isAdmin: false,
        assignedTeams: [teams[1], teams[2]],
      );

      expect(shouldLock, isTrue);
    });
  });

  group('LaegetaskerAccessLogic.visibleTeams', () {
    test('shows all teams for admin-like unlocked state', () {
      final visible = LaegetaskerAccessLogic.visibleTeams(
        teams: teams,
        teamLocked: false,
        assignedTeams: [teams[1], teams[2]],
      );

      expect(visible.map((team) => team.id), ['u15', 'u16', 'u17']);
    });

    test('shows only assigned teams for locked coach state', () {
      final visible = LaegetaskerAccessLogic.visibleTeams(
        teams: teams,
        teamLocked: true,
        assignedTeams: [teams[1], teams[2]],
      );

      expect(visible.map((team) => team.id), ['u16', 'u17']);
    });

    test('shows all teams when no assigned teams exist', () {
      final visible = LaegetaskerAccessLogic.visibleTeams(
        teams: teams,
        teamLocked: false,
        assignedTeams: const [],
      );

      expect(visible.map((team) => team.id), ['u15', 'u16', 'u17']);
    });
  });
}
