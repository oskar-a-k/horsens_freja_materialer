import '../models/team_model.dart';

class LaegetaskerAccessLogic {
  static bool shouldLockTeams({
    required bool isAdmin,
    required List<TeamModel> assignedTeams,
  }) {
    return !isAdmin && assignedTeams.isNotEmpty;
  }

  static List<TeamModel> visibleTeams({
    required List<TeamModel> teams,
    required bool teamLocked,
    required List<TeamModel> assignedTeams,
  }) {
    if (!teamLocked || assignedTeams.isEmpty) {
      return teams;
    }

    final assignedIds = assignedTeams.map((team) => team.id).toSet();

    return [
      for (final team in teams)
        if (assignedIds.contains(team.id)) team,
    ];
  }
}
