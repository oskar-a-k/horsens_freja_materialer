class TransactionModel {
  final String id;
  final String materialId;
  final String type;
  final int quantity;
  final String? teamId;
  final String performedBy;
  final String? note;
  final DateTime timestamp;

  TransactionModel({
    required this.id,
    required this.materialId,
    required this.type,
    required this.quantity,
    this.teamId,
    required this.performedBy,
    this.note,
    required this.timestamp,
  });

  factory TransactionModel.fromMap(String id, Map<String, dynamic> map) {
    return TransactionModel(
      id: id,
      materialId: map['materialId'] as String? ?? '',
      type: map['type'] as String? ?? '',
      quantity: (map['quantity'] as num?)?.toInt() ?? 0,
      teamId: map['teamId'] as String?,
      performedBy: map['performedBy'] as String? ?? '',
      note: map['note'] as String?,
      timestamp: map['timestamp'] is int
          ? DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int)
          : map['timestamp'] is String
          ? DateTime.tryParse(map['timestamp'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'materialId': materialId,
      'type': type,
      'quantity': quantity,
      'teamId': teamId,
      'performedBy': performedBy,
      'note': note,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}
