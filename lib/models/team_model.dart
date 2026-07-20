class TeamKitSetModel {
  final String id;
  final String setNumber;
  final String jerseyColor;
  final String jerseySize;
  final String jerseyStatus;
  final String shortsColor;
  final String shortsSize;
  final String shortsStatus;
  final String socksColor;
  final String socksSize;
  final String socksStatus;
  final String duffelbagColor;
  final String duffelbagStatus;
  final String? note;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  TeamKitSetModel({
    required this.id,
    required this.setNumber,
    this.jerseyColor = '',
    this.jerseySize = '',
    this.jerseyStatus = 'ok',
    this.shortsColor = '',
    this.shortsSize = '',
    this.shortsStatus = 'ok',
    this.socksColor = '',
    this.socksSize = '',
    this.socksStatus = 'ok',
    this.duffelbagColor = '',
    this.duffelbagStatus = 'ok',
    this.note,
    this.createdAt,
    this.updatedAt,
  });

  TeamKitSetModel copyWith({
    String? id,
    String? setNumber,
    String? jerseyColor,
    String? jerseySize,
    String? jerseyStatus,
    String? shortsColor,
    String? shortsSize,
    String? shortsStatus,
    String? socksColor,
    String? socksSize,
    String? socksStatus,
    String? duffelbagColor,
    String? duffelbagStatus,
    String? note,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return TeamKitSetModel(
      id: id ?? this.id,
      setNumber: setNumber ?? this.setNumber,
      jerseyColor: jerseyColor ?? this.jerseyColor,
      jerseySize: jerseySize ?? this.jerseySize,
      jerseyStatus: jerseyStatus ?? this.jerseyStatus,
      shortsColor: shortsColor ?? this.shortsColor,
      shortsSize: shortsSize ?? this.shortsSize,
      shortsStatus: shortsStatus ?? this.shortsStatus,
      socksColor: socksColor ?? this.socksColor,
      socksSize: socksSize ?? this.socksSize,
      socksStatus: socksStatus ?? this.socksStatus,
      duffelbagColor: duffelbagColor ?? this.duffelbagColor,
      duffelbagStatus: duffelbagStatus ?? this.duffelbagStatus,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory TeamKitSetModel.fromMap(Map<String, dynamic> map) {
    return TeamKitSetModel(
      id: map['id'] as String? ?? '',
      setNumber: map['setNumber'] as String? ?? '',
      jerseyColor: map['jerseyColor'] as String? ?? '',
      jerseySize: map['jerseySize'] as String? ?? '',
      jerseyStatus: map['jerseyStatus'] as String? ?? 'ok',
      shortsColor: map['shortsColor'] as String? ?? '',
      shortsSize: map['shortsSize'] as String? ?? '',
      shortsStatus: map['shortsStatus'] as String? ?? 'ok',
      socksColor: map['socksColor'] as String? ?? '',
      socksSize: map['socksSize'] as String? ?? '',
      socksStatus: map['socksStatus'] as String? ?? 'ok',
      duffelbagColor: map['duffelbagColor'] as String? ?? '',
      duffelbagStatus: map['duffelbagStatus'] as String? ?? 'ok',
      note: map['note'] as String?,
      createdAt: map['createdAt'] is String
          ? DateTime.tryParse(map['createdAt'] as String)
          : null,
      updatedAt: map['updatedAt'] is String
          ? DateTime.tryParse(map['updatedAt'] as String)
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'setNumber': setNumber,
      'jerseyColor': jerseyColor,
      'jerseySize': jerseySize,
      'jerseyStatus': jerseyStatus,
      'shortsColor': shortsColor,
      'shortsSize': shortsSize,
      'shortsStatus': shortsStatus,
      'socksColor': socksColor,
      'socksSize': socksSize,
      'socksStatus': socksStatus,
      'duffelbagColor': duffelbagColor,
      'duffelbagStatus': duffelbagStatus,
      'note': note,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }
}

class TeamModel {
  final String id;
  final String name;
  final bool needsMedicalBag;
  final String? coachId;
  final String? note;
  final Map<String, int> holdings;
  final Map<String, int> expectedHoldings;
  final List<TeamKitSetModel> kitSets;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  TeamModel({
    required this.id,
    required this.name,
    this.needsMedicalBag = false,
    this.coachId,
    this.note,
    Map<String, int>? holdings,
    Map<String, int>? expectedHoldings,
    List<TeamKitSetModel>? kitSets,
    this.createdAt,
    this.updatedAt,
  }) : holdings = holdings ?? {},
       expectedHoldings = expectedHoldings ?? {},
       kitSets = kitSets ?? [];

  TeamModel copyWith({
    String? id,
    String? name,
    bool? needsMedicalBag,
    String? coachId,
    String? note,
    Map<String, int>? holdings,
    Map<String, int>? expectedHoldings,
    List<TeamKitSetModel>? kitSets,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return TeamModel(
      id: id ?? this.id,
      name: name ?? this.name,
      needsMedicalBag: needsMedicalBag ?? this.needsMedicalBag,
      coachId: coachId ?? this.coachId,
      note: note ?? this.note,
      holdings: holdings ?? Map.from(this.holdings),
      expectedHoldings: expectedHoldings ?? Map.from(this.expectedHoldings),
      kitSets: kitSets ?? List<TeamKitSetModel>.from(this.kitSets),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory TeamModel.fromMap(String id, Map<String, dynamic> map) {
    final rawHoldings = map['holdings'] as Map<String, dynamic>?;
    final holdings = <String, int>{};
    if (rawHoldings != null) {
      rawHoldings.forEach((k, v) {
        holdings[k] = (v as num).toInt();
      });
    }

    final rawExpected = map['expectedHoldings'] as Map<String, dynamic>?;
    final expectedHoldings = <String, int>{};
    if (rawExpected != null) {
      rawExpected.forEach((k, v) {
        expectedHoldings[k] = (v as num).toInt();
      });
    }

    final rawKitSets = map['kitSets'] as List<dynamic>?;
    final kitSets = <TeamKitSetModel>[];
    if (rawKitSets != null) {
      for (final rawKitSet in rawKitSets) {
        if (rawKitSet is Map) {
          kitSets.add(
            TeamKitSetModel.fromMap(Map<String, dynamic>.from(rawKitSet)),
          );
        }
      }
    }

    return TeamModel(
      id: id,
      name: map['name'] as String? ?? '',
      needsMedicalBag: map['needsMedicalBag'] as bool? ?? false,
      coachId: map['coachId'] as String?,
      note: map['note'] as String?,
      holdings: holdings,
      expectedHoldings: expectedHoldings,
      kitSets: kitSets,
      createdAt: map['createdAt'] is String
          ? DateTime.tryParse(map['createdAt'] as String)
          : null,
      updatedAt: map['updatedAt'] is String
          ? DateTime.tryParse(map['updatedAt'] as String)
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'needsMedicalBag': needsMedicalBag,
      'coachId': coachId,
      'note': note,
      'holdings': holdings.map((k, v) => MapEntry(k, v)),
      'expectedHoldings': expectedHoldings.map((k, v) => MapEntry(k, v)),
      'kitSets': kitSets.map((kitSet) => kitSet.toMap()).toList(),
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }
}

Iterable<String> teamMaterialIds(TeamModel team) {
  return {...team.holdings.keys, ...team.expectedHoldings.keys};
}

int teamActualMaterialCount(TeamModel team, String materialId) {
  return team.holdings[materialId] ?? 0;
}

int? teamExpectedMaterialCount(TeamModel team, String materialId) {
  return team.expectedHoldings[materialId];
}

int teamMissingMaterialCount(TeamModel team, String materialId) {
  final expected = team.expectedHoldings[materialId];
  if (expected == null) return 0;
  final actual = team.holdings[materialId] ?? 0;
  final missing = expected - actual;
  return missing > 0 ? missing : 0;
}

Iterable<String> teamMaterialIdsFromMap(Map<String, dynamic> teamData) {
  final holdings = teamData['holdings'] as Map<String, dynamic>? ?? {};
  final expected = teamData['expectedHoldings'] as Map<String, dynamic>? ?? {};
  return {...holdings.keys, ...expected.keys};
}

int teamActualMaterialCountFromMap(
  Map<String, dynamic> teamData,
  String materialId,
) {
  final holdings = teamData['holdings'] as Map<String, dynamic>? ?? {};
  return (holdings[materialId] as num?)?.toInt() ?? 0;
}

int? teamExpectedMaterialCountFromMap(
  Map<String, dynamic> teamData,
  String materialId,
) {
  final expected = teamData['expectedHoldings'] as Map<String, dynamic>? ?? {};
  return (expected[materialId] as num?)?.toInt();
}

int teamMissingMaterialCountFromMap(
  Map<String, dynamic> teamData,
  String materialId,
) {
  final expected = teamExpectedMaterialCountFromMap(teamData, materialId);
  if (expected == null) return 0;
  final actual = teamActualMaterialCountFromMap(teamData, materialId);
  final missing = expected - actual;
  return missing > 0 ? missing : 0;
}
