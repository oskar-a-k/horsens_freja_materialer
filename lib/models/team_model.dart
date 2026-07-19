class TeamKitSetModel {
  final String id;
  final String setNumber;
  final String jerseySize;
  final String jerseyStatus;
  final String shortsSize;
  final String shortsStatus;
  final String socksSize;
  final String socksStatus;
  final String duffelbagStatus;
  final String? note;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  TeamKitSetModel({
    required this.id,
    required this.setNumber,
    this.jerseySize = '',
    this.jerseyStatus = 'ok',
    this.shortsSize = '',
    this.shortsStatus = 'ok',
    this.socksSize = '',
    this.socksStatus = 'ok',
    this.duffelbagStatus = 'ok',
    this.note,
    this.createdAt,
    this.updatedAt,
  });

  TeamKitSetModel copyWith({
    String? id,
    String? setNumber,
    String? jerseySize,
    String? jerseyStatus,
    String? shortsSize,
    String? shortsStatus,
    String? socksSize,
    String? socksStatus,
    String? duffelbagStatus,
    String? note,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return TeamKitSetModel(
      id: id ?? this.id,
      setNumber: setNumber ?? this.setNumber,
      jerseySize: jerseySize ?? this.jerseySize,
      jerseyStatus: jerseyStatus ?? this.jerseyStatus,
      shortsSize: shortsSize ?? this.shortsSize,
      shortsStatus: shortsStatus ?? this.shortsStatus,
      socksSize: socksSize ?? this.socksSize,
      socksStatus: socksStatus ?? this.socksStatus,
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
      jerseySize: map['jerseySize'] as String? ?? '',
      jerseyStatus: map['jerseyStatus'] as String? ?? 'ok',
      shortsSize: map['shortsSize'] as String? ?? '',
      shortsStatus: map['shortsStatus'] as String? ?? 'ok',
      socksSize: map['socksSize'] as String? ?? '',
      socksStatus: map['socksStatus'] as String? ?? 'ok',
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
      'jerseySize': jerseySize,
      'jerseyStatus': jerseyStatus,
      'shortsSize': shortsSize,
      'shortsStatus': shortsStatus,
      'socksSize': socksSize,
      'socksStatus': socksStatus,
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
