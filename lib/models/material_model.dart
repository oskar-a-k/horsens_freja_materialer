class MaterialModel {
  final String id;
  final String name;
  final String? variant;
  final String? sku;
  final String category;
  final String unit;
  final int totalInStock;
  final int minThreshold;
  final String? photoUrl;
  final String? supplier;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  MaterialModel({
    required this.id,
    required this.name,
    this.variant,
    this.sku,
    required this.category,
    required this.unit,
    required this.totalInStock,
    required this.minThreshold,
    this.photoUrl,
    this.supplier,
    this.createdAt,
    this.updatedAt,
  });

  MaterialModel copyWith({
    String? id,
    String? name,
    String? variant,
    String? sku,
    String? category,
    String? unit,
    int? totalInStock,
    int? minThreshold,
    String? photoUrl,
    String? supplier,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return MaterialModel(
      id: id ?? this.id,
      name: name ?? this.name,
      variant: variant ?? this.variant,
      sku: sku ?? this.sku,
      category: category ?? this.category,
      unit: unit ?? this.unit,
      totalInStock: totalInStock ?? this.totalInStock,
      minThreshold: minThreshold ?? this.minThreshold,
      photoUrl: photoUrl ?? this.photoUrl,
      supplier: supplier ?? this.supplier,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory MaterialModel.fromMap(String id, Map<String, dynamic> map) {
    return MaterialModel(
      id: id,
      name: map['name'] as String? ?? '',
      variant: map['variant'] as String?,
      sku: map['sku'] as String?,
      category: map['category'] as String? ?? '',
      unit: map['unit'] as String? ?? 'stk',
      totalInStock: (map['totalInStock'] as num?)?.toInt() ?? 0,
      minThreshold: (map['minThreshold'] as num?)?.toInt() ?? 0,
      photoUrl: map['photoUrl'] as String?,
      supplier: map['supplier'] as String?,
      createdAt: map['createdAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int)
          : map['createdAt'] is String
          ? DateTime.tryParse(map['createdAt'] as String)
          : null,
      updatedAt: map['updatedAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(map['updatedAt'] as int)
          : map['updatedAt'] is String
          ? DateTime.tryParse(map['updatedAt'] as String)
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'variant': variant,
      'sku': sku,
      'category': category,
      'unit': unit,
      'totalInStock': totalInStock,
      'minThreshold': minThreshold,
      'photoUrl': photoUrl,
      'supplier': supplier,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }
}
