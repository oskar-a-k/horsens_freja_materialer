class TeamModel {
  final String id;
  final String name;
  final String? coachId;
  final String? note;
  final Map<String, int> holdings;
  final Map<String, int> expectedHoldings;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  TeamModel({
    required this.id,
    required this.name,
    this.coachId,
    this.note,
    Map<String, int>? holdings,
    Map<String, int>? expectedHoldings,
    this.createdAt,
    this.updatedAt,
  }) : holdings = holdings ?? {},
       expectedHoldings = expectedHoldings ?? {};

  TeamModel copyWith({
    String? id,
    String? name,
    String? coachId,
    String? note,
    Map<String, int>? holdings,
    Map<String, int>? expectedHoldings,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return TeamModel(
      id: id ?? this.id,
      name: name ?? this.name,
      coachId: coachId ?? this.coachId,
      note: note ?? this.note,
      holdings: holdings ?? Map.from(this.holdings),
      expectedHoldings: expectedHoldings ?? Map.from(this.expectedHoldings),
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

    return TeamModel(
      id: id,
      name: map['name'] as String? ?? '',
      coachId: map['coachId'] as String?,
      note: map['note'] as String?,
      holdings: holdings,
      expectedHoldings: expectedHoldings,
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
      'coachId': coachId,
      'note': note,
      'holdings': holdings.map((k, v) => MapEntry(k, v)),
      'expectedHoldings': expectedHoldings.map((k, v) => MapEntry(k, v)),
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }
}
