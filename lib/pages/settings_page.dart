import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const Set<String> _adminOverrideEmails = {
    'materialer@horsensfreja.dk',
  };

  final TextEditingController _adminPasswordController =
      TextEditingController();
  final TextEditingController _newEmailController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  late final Future<bool> _adminFuture;
  bool _loading = false;
  String? _message;
  String? _errorMessage;
  String _selectedRole = 'viewer';
  Set<String> _selectedPermissions = {'hold'};

  static const Map<String, List<String>> _permissionsByRole = {
    'admin': ['hold', 'laegetasker', 'lager', 'mangelliste'],
    'manager': ['hold', 'laegetasker', 'lager', 'mangelliste'],
    'coach': ['hold', 'mangelliste'],
    'viewer': ['hold'],
  };

  static const Map<String, String> _roleLabels = {
    'admin': 'Admin',
    'manager': 'Materialeansvarlig',
    'coach': 'Træner',
    'viewer': 'Bruger',
  };

  static const Map<String, String> _roleDescriptions = {
    'admin': 'Fuld adgang til alle sider og brugeradministration.',
    'manager': 'Adgang til alle materialesider, men ikke brugeradministration.',
    'coach': 'Adgang til hold og mangelliste.',
    'viewer': 'Kun adgang til holdoversigt.',
  };

  static const Map<String, String> _pageLabels = {
    'hold': 'Hold',
    'laegetasker': 'Lægetasker',
    'lager': 'Lager',
    'mangelliste': 'Mangelliste',
  };

  static const Map<String, String> _cadenceLabels = {
    'every_2_weeks': 'Hver 2. uge',
    'monthly': 'Månedligt',
  };

  DateTime? _toDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  int _cadenceDays(String cadence) {
    return cadence == 'monthly' ? 30 : 14;
  }

  bool _hasLaegetaskeAccess(Map<String, dynamic> data) {
    final permissions = List<String>.from(
      data['permissions'] as List<dynamic>? ?? const <String>[],
    );
    return permissions.contains('laegetasker');
  }

  @override
  void initState() {
    super.initState();
    _adminFuture = _isAdminUser();
  }

  Future<bool> _isAdminUser() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return false;

    final currentEmail = currentUser.email?.toLowerCase();
    final bool hasOverrideAdmin =
        currentEmail != null && _adminOverrideEmails.contains(currentEmail);

    final userDoc = FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid);
    final snapshot = await userDoc.get();
    final bool isAdmin =
        snapshot.exists && (snapshot.data()?['isAdmin'] as bool? ?? false);
    return isAdmin || hasOverrideAdmin;
  }

  Future<void> _createUser() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final currentEmail = currentUser?.email;
    final adminPassword = _adminPasswordController.text.trim();
    final newEmail = _newEmailController.text.trim();
    final newPassword = _newPasswordController.text.trim();
    final role = _selectedRole;
    final permissions = _selectedPermissions.toList();

    if (newEmail.isEmpty || newPassword.isEmpty || adminPassword.isEmpty) {
      setState(() {
        _errorMessage = 'Udfyld alle felter.';
        _message = null;
      });
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
      _message = null;
    });

    try {
      final newUserCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: newEmail,
            password: newPassword,
          );

      final newUser = newUserCredential.user;
      if (newUser == null) {
        throw FirebaseAuthException(
          code: 'user-creation-failed',
          message: 'Kan ikke oprette bruger.',
        );
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(newUser.uid)
          .set({
            'email': newEmail,
            'role': role,
            'permissions': permissions,
            'isAdmin': role == 'admin',
          });

      if (currentEmail != null) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: currentEmail,
          password: adminPassword,
        );
      }

      setState(() {
        _message = 'Bruger oprettet med rollen ${_roleLabels[role]}.';
        _errorMessage = null;
      });
      _newEmailController.clear();
      _newPasswordController.clear();
      _adminPasswordController.clear();
      _selectedRole = 'viewer';
    } on FirebaseAuthException catch (error) {
      setState(() {
        _errorMessage = error.message ?? 'Der skete en fejl.';
        _message = null;
      });
    } catch (_) {
      setState(() {
        _errorMessage = 'Der skete en ukendt fejl.';
        _message = null;
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
  }

  Future<void> _editUserSetup(
    QueryDocumentSnapshot<Map<String, dynamic>> userDoc,
  ) async {
    final data = userDoc.data();
    String role = data['role'] as String? ?? 'viewer';
    final selectedPermissions = Set<String>.from(
      List<String>.from(data['permissions'] as List<dynamic>? ?? ['hold']),
    );
    String cadence = data['reportingCadence'] as String? ?? 'every_2_weeks';
    String? teamId = data['teamId'] as String?;
    String? teamName = data['teamName'] as String?;

    final teamsSnapshot = await FirebaseFirestore.instance
        .collection('teams')
        .get();

    final teams =
        teamsSnapshot.docs
            .map(
              (doc) => {
                'id': doc.id,
                'name': doc.data()['name'] as String? ?? 'Ukendt',
              },
            )
            .toList()
          ..sort(
            (a, b) => (a['name'] as String).toLowerCase().compareTo(
              (b['name'] as String).toLowerCase(),
            ),
          );

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) {
        final dialogNavigator = Navigator.of(context);
        final messenger = ScaffoldMessenger.of(context);
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Redigér bruger'),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Email: ${data['email'] ?? 'ukendt'}'),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: role,
                      decoration: const InputDecoration(labelText: 'Rolle'),
                      items: _roleLabels.entries
                          .map(
                            (entry) => DropdownMenuItem<String>(
                              value: entry.key,
                              child: Text(entry.value),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setStateDialog(() {
                          role = value;
                          selectedPermissions
                            ..clear()
                            ..addAll(_permissionsByRole[value] ?? ['hold']);
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Sider brugeren må se',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _pageLabels.entries.map((entry) {
                        final hasPermission = selectedPermissions.contains(
                          entry.key,
                        );
                        return FilterChip(
                          selected: hasPermission,
                          label: Text(entry.value),
                          onSelected: (selected) {
                            setStateDialog(() {
                              if (selected) {
                                selectedPermissions.add(entry.key);
                              } else {
                                selectedPermissions.remove(entry.key);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: cadence,
                      decoration: const InputDecoration(
                        labelText: 'Statusfrekvens',
                      ),
                      items: _cadenceLabels.entries
                          .map(
                            (entry) => DropdownMenuItem<String>(
                              value: entry.key,
                              child: Text(entry.value),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setStateDialog(() => cadence = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String?>(
                      initialValue: teamId,
                      decoration: const InputDecoration(
                        labelText: 'Tilknyt hold',
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Intet hold'),
                        ),
                        ...teams.map(
                          (team) => DropdownMenuItem<String?>(
                            value: team['id'] as String,
                            child: Text(team['name'] as String),
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        setStateDialog(() {
                          teamId = value;
                          if (value == null) {
                            teamName = null;
                          } else {
                            final found = teams.firstWhere(
                              (t) => t['id'] == value,
                              orElse: () => {'id': value, 'name': ''},
                            );
                            teamName = found['name'] as String;
                          }
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => dialogNavigator.pop(),
                  child: const Text('Annuller'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await FirebaseFirestore.instance
                        .collection('users')
                        .doc(userDoc.id)
                        .set({
                          'role': role,
                          'permissions': selectedPermissions.toList(),
                          'isAdmin': role == 'admin',
                          'reportingCadence': cadence,
                          'teamId': teamId,
                          'teamName': teamName,
                        }, SetOptions(merge: true));
                    if (!mounted) return;
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Bruger opdateret.')),
                    );
                    dialogNavigator.pop();
                  },
                  child: const Text('Gem'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text('Indstillinger')),
      body: FutureBuilder<bool>(
        future: _adminFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.data != true) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Du har ikke adgang til denne side.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.all(16),
            child: ListView(
              children: [
                if (user != null)
                  Text('Logget ind som: ${user.email ?? 'ukendt'}'),
                const SizedBox(height: 16),
                const Text(
                  'Opret ny bruger',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _newEmailController,
                  decoration: const InputDecoration(
                    labelText: 'Ny brugers email',
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _newPasswordController,
                  decoration: const InputDecoration(
                    labelText: 'Ny brugers adgangskode',
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 12),
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Brugerrolle',
                    border: OutlineInputBorder(),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedRole,
                      isExpanded: true,
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _selectedRole = value;
                            _selectedPermissions = Set<String>.from(
                              _permissionsByRole[value] ?? ['hold'],
                            );
                          });
                        }
                      },
                      items: _roleLabels.entries
                          .map(
                            (entry) => DropdownMenuItem(
                              value: entry.key,
                              child: Text(entry.value),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _roleDescriptions[_selectedRole] ?? '',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Vælg sider brugeren må se',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _pageLabels.entries.map((entry) {
                    final hasPermission = _selectedPermissions.contains(
                      entry.key,
                    );
                    return FilterChip(
                      selected: hasPermission,
                      label: Text(entry.value),
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _selectedPermissions.add(entry.key);
                          } else {
                            _selectedPermissions.remove(entry.key);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _adminPasswordController,
                  decoration: const InputDecoration(
                    labelText: 'Din egen adgangskode',
                    hintText:
                        'Bruges til at logge tilbage ind efter oprettelse',
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _loading ? null : _createUser,
                  child: _loading
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Opret bruger'),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _signOut,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text('Log ud'),
                ),
                if (_message != null) ...[
                  const SizedBox(height: 16),
                  Text(_message!, style: const TextStyle(color: Colors.green)),
                ],
                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ],
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 12),
                const Text(
                  'Brugeroversigt og holdtilknytning',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.all(12),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }

                    if (snapshot.hasError) {
                      return Text(
                        'Kunne ikke hente brugere: ${snapshot.error}',
                      );
                    }

                    final docs = snapshot.data?.docs ?? [];
                    if (docs.isEmpty) {
                      return const Text('Ingen brugere fundet.');
                    }

                    final sorted = [...docs]
                      ..sort((a, b) {
                        final aEmail = (a.data()['email'] as String? ?? '')
                            .toLowerCase();
                        final bEmail = (b.data()['email'] as String? ?? '')
                            .toLowerCase();
                        return aEmail.compareTo(bEmail);
                      });

                    final now = DateTime.now();
                    final overdue = sorted.where((doc) {
                      final data = doc.data();
                      if (!_hasLaegetaskeAccess(data)) return false;

                      final teamId = data['teamId'] as String?;
                      final teamName = data['teamName'] as String?;
                      final hasTeam =
                          (teamId != null && teamId.isNotEmpty) ||
                          (teamName != null && teamName.isNotEmpty);
                      if (!hasTeam) return false;

                      final cadence =
                          data['reportingCadence'] as String? ??
                          'every_2_weeks';
                      final dueDays = _cadenceDays(cadence);

                      final lastStatus = _toDateTime(data['lastStatusAt']);
                      if (lastStatus == null) return true;

                      final daysSince = now.difference(lastStatus).inDays;
                      return daysSince >= dueDays;
                    }).toList();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Manglende statusrapporter',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        if (overdue.isEmpty)
                          const Text(
                            'Ingen brugere er for sent på status lige nu.',
                          )
                        else
                          ...overdue.map((doc) {
                            final data = doc.data();
                            final email = data['email'] as String? ?? 'ukendt';
                            final teamName =
                                data['teamName'] as String? ?? 'ikke sat';
                            final cadence =
                                data['reportingCadence'] as String? ??
                                'every_2_weeks';
                            final cadenceLabel =
                                _cadenceLabels[cadence] ??
                                _cadenceLabels['every_2_weeks']!;
                            final dueDays = _cadenceDays(cadence);
                            final lastStatus = _toDateTime(
                              data['lastStatusAt'],
                            );
                            final daysSince = lastStatus == null
                                ? null
                                : now.difference(lastStatus).inDays;
                            final lateDays = lastStatus == null
                                ? null
                                : daysSince! - dueDays;

                            return Card(
                              color: Colors.red.shade50,
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              child: ListTile(
                                title: Text(email),
                                subtitle: Text(
                                  lastStatus == null
                                      ? 'Hold: $teamName · Status: $cadenceLabel · Har ikke indsendt endnu'
                                      : 'Hold: $teamName · Status: $cadenceLabel · Forsinket: ${lateDays! < 0 ? 0 : lateDays} dage',
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.edit_calendar),
                                  tooltip: 'Redigér bruger',
                                  onPressed: () => _editUserSetup(doc),
                                ),
                              ),
                            );
                          }),
                        const SizedBox(height: 14),
                        const Divider(),
                        const SizedBox(height: 8),
                        ...sorted.map((doc) {
                          final data = doc.data();
                          final email = data['email'] as String? ?? 'ukendt';
                          final role = data['role'] as String? ?? 'viewer';
                          final teamName = data['teamName'] as String?;
                          final cadence = data['reportingCadence'] as String?;
                          final cadenceLabel =
                              _cadenceLabels[cadence] ??
                              _cadenceLabels['every_2_weeks']!;

                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            child: ListTile(
                              title: Text(email),
                              subtitle: Text(
                                'Rolle: ${_roleLabels[role] ?? role} · Hold: ${teamName ?? 'ikke sat'} · Status: $cadenceLabel',
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.edit),
                                tooltip: 'Redigér bruger',
                                onPressed: () => _editUserSetup(doc),
                              ),
                            ),
                          );
                        }),
                      ],
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
