import '../models/team_model.dart';

class LaegetaskerAccessLogic {
  static bool shouldLockTeams({
    required bool isAdmin,
    required TeamModel? assignedTeam,
  }) {
    return !isAdmin && assignedTeam != null;
  }

  static List<TeamModel> visibleTeams({
    required List<TeamModel> teams,
    required bool teamLocked,
    required TeamModel? assignedTeam,
  }) {
    if (!teamLocked || assignedTeam == null) {
      return teams;
    }

    return [
      for (final team in teams)
        if (team.id == assignedTeam.id) team,
    ];
  }
}
