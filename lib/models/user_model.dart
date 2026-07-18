class UserModel {
  final String uid;
  final String name;
  final String email;
  final String role;
  final List<String> teams;

  UserModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    List<String>? teams,
  }) : teams = teams ?? [];

  UserModel copyWith({
    String? uid,
    String? name,
    String? email,
    String? role,
    List<String>? teams,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      name: name ?? this.name,
      email: email ?? this.email,
      role: role ?? this.role,
      teams: teams ?? List.from(this.teams),
    );
  }

  factory UserModel.fromMap(String uid, Map<String, dynamic> map) {
    final rawTeams = map['teams'] as List<dynamic>?;
    return UserModel(
      uid: uid,
      name: map['name'] as String? ?? '',
      email: map['email'] as String? ?? '',
      role: map['role'] as String? ?? 'coach',
      teams: rawTeams?.map((e) => e as String).toList() ?? [],
    );
  }

  Map<String, dynamic> toMap() {
    return {'name': name, 'email': email, 'role': role, 'teams': teams};
  }
}
