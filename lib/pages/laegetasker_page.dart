import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/material_model.dart';
import '../models/team_model.dart';
import '../services/inventory_service.dart';
import '../services/laegetasker_access_logic.dart';
import '../services/shortage_case_service.dart';

class LaegetaskerPage extends StatefulWidget {
  final InventoryService service;

  const LaegetaskerPage({super.key, required this.service});

  @override
  State<LaegetaskerPage> createState() => _LaegetaskerPageState();
}

class _LaegetaskerPageState extends State<LaegetaskerPage> {
  static const Set<String> _adminOverrideEmails = {
    'materialer@horsensfreja.dk',
  };

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late final ShortageCaseService _shortageCaseService = ShortageCaseService(
    firestore: _firestore,
  );

  List<TeamModel> _teams = [];
  List<MaterialModel> _materials = [];
  List<TeamModel> _assignedTeams = [];
  bool _loading = true;
  String? _error;
  String _reportingCadence = '';
  bool _teamLocked = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final teamsFuture = widget.service.listTeams();
      final materialsFuture = widget.service.listMaterials();
      final teams = await teamsFuture;
      final materials = await materialsFuture;

      final initialTeams = <TeamModel>[];
      final user = FirebaseAuth.instance.currentUser;
      var isAdmin = false;

      if (user != null) {
        final userDoc = await _firestore
            .collection('users')
            .doc(user.uid)
            .get();
        final userData = userDoc.data();
        final role = (userData?['role'] as String? ?? '').toLowerCase();
        final email = user.email?.toLowerCase();
        isAdmin =
            (userData?['isAdmin'] as bool? ?? false) ||
            role == 'admin' ||
            (email != null && _adminOverrideEmails.contains(email));

        final cadence = userData?['reportingCadence'] as String?;
        if (cadence != null && cadence.isNotEmpty) {
          _reportingCadence = cadence;
        }

        final userTeamIds = List<String>.from(
          userData?['teams'] as List<dynamic>? ?? const <String>[],
        );
        final userTeamNames = List<String>.from(
          userData?['teamNames'] as List<dynamic>? ?? const <String>[],
        );
        final userTeamId = userData?['teamId'] as String?;
        final userTeamName = userData?['teamName'] as String?;

        for (final team in teams) {
          if (userTeamIds.contains(team.id)) {
            initialTeams.add(team);
          }
        }

        if (initialTeams.isEmpty && userTeamNames.isNotEmpty) {
          final loweredNames = userTeamNames
              .map((name) => name.toLowerCase())
              .toSet();
          for (final team in teams) {
            if (loweredNames.contains(team.name.toLowerCase())) {
              initialTeams.add(team);
            }
          }
        }

        if (initialTeams.isEmpty &&
            userTeamId != null &&
            userTeamId.isNotEmpty) {
          for (final team in teams) {
            if (team.id == userTeamId) {
              initialTeams.add(team);
              break;
            }
          }
        }

        if (initialTeams.isEmpty &&
            userTeamName != null &&
            userTeamName.isNotEmpty) {
          for (final team in teams) {
            if (team.name.toLowerCase() == userTeamName.toLowerCase()) {
              initialTeams.add(team);
              break;
            }
          }
        }

        if (initialTeams.isEmpty) {
          for (final team in teams) {
            if (team.coachId == user.uid) {
              initialTeams.add(team);
            }
          }
        }

        _teamLocked = LaegetaskerAccessLogic.shouldLockTeams(
          isAdmin: isAdmin,
          assignedTeams: initialTeams,
        );
      }

      var resolvedAssignedTeams = initialTeams;
      if (resolvedAssignedTeams.isEmpty && _assignedTeams.isNotEmpty) {
        resolvedAssignedTeams = _assignedTeams;
      }
      if (resolvedAssignedTeams.isEmpty && teams.length == 1) {
        resolvedAssignedTeams = [teams.first];
      }

      if (!mounted) return;
      setState(() {
        _teams = teams;
        _materials = materials;
        _assignedTeams = resolvedAssignedTeams;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Kunne ikke hente lægetaske-data: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  MaterialModel _materialForId(String id) {
    return _materials.firstWhere(
      (m) => m.id == id,
      orElse: () => MaterialModel(
        id: id,
        name: 'Ukendt',
        sku: null,
        category: '',
        unit: '',
        totalInStock: 0,
        minThreshold: 0,
      ),
    );
  }

  String _materialLabel(MaterialModel material) {
    return (material.variant == null || material.variant!.isEmpty)
        ? material.name
        : '${material.name} · ${material.variant}';
  }

  Future<void> _reportShortage({
    required TeamModel team,
    required MaterialModel material,
    required int currentQty,
  }) async {
    final qtyCtrl = TextEditingController(text: '1');
    final noteCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) {
        final dialogNavigator = Navigator.of(context);
        final messenger = ScaffoldMessenger.of(context);
        return AlertDialog(
          title: const Text('Meld mangel i lægetaske'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_materialLabel(material)),
              const SizedBox(height: 8),
              Text('Status nu: $currentQty ${material.unit}'),
              TextField(
                controller: qtyCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Mangler antal'),
              ),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(
                  labelText: 'Begrundelse (påkrævet)',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => dialogNavigator.pop(),
              child: const Text('Annuller'),
            ),
            ElevatedButton(
              onPressed: () async {
                final qty = int.tryParse(qtyCtrl.text.trim()) ?? 0;
                final reason = noteCtrl.text.trim();
                if (qty <= 0) return;
                if (reason.isEmpty) {
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Skriv begrundelse for manglen.'),
                    ),
                  );
                  return;
                }

                final user = FirebaseAuth.instance.currentUser;
                await _shortageCaseService.upsertOpenCase(
                  teamId: team.id,
                  teamName: team.name,
                  materialId: material.id,
                  materialName: _materialLabel(material),
                  reportedQuantity: qty,
                  note: reason,
                  source: 'coach_report',
                  reportedByUid: user?.uid,
                  reportedByEmail: user?.email,
                );

                if (!mounted) return;
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Sag er registreret/opdateret.'),
                  ),
                );
                dialogNavigator.pop();
              },
              child: const Text('Gem'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _submitStatusReport(TeamModel team) async {
    final noteCtrl = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (context) {
        final dialogNavigator = Navigator.of(context);
        final messenger = ScaffoldMessenger.of(context);
        return AlertDialog(
          title: const Text('Indsend statusrapport'),
          content: TextField(
            controller: noteCtrl,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Status og forklaring',
              hintText:
                  'Skriv kort status for lægetasken, og hvorfor eventuelle varer mangler.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => dialogNavigator.pop(),
              child: const Text('Annuller'),
            ),
            ElevatedButton(
              onPressed: () async {
                final note = noteCtrl.text.trim();
                if (note.isEmpty) return;

                final user = FirebaseAuth.instance.currentUser;
                await _firestore.collection('bag_status_reports').add({
                  'teamId': team.id,
                  'teamName': team.name,
                  'note': note,
                  'createdAt': FieldValue.serverTimestamp(),
                  'reportedByUid': user?.uid,
                  'reportedByEmail': user?.email,
                });

                if (user != null) {
                  await _firestore.collection('users').doc(user.uid).set({
                    'lastStatusAt': FieldValue.serverTimestamp(),
                  }, SetOptions(merge: true));
                }

                if (!mounted) return;
                messenger.showSnackBar(
                  const SnackBar(content: Text('Statusrapport gemt.')),
                );
                dialogNavigator.pop();
              },
              child: const Text('Gem'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Lægetasker')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_error!),
          ),
        ),
      );
    }

    final user = FirebaseAuth.instance.currentUser;
    final cadenceLabel = _reportingCadence == 'monthly'
        ? 'Månedligt'
        : _reportingCadence == 'every_2_weeks'
        ? 'Hver 2. uge'
        : 'Ingen fast status';
    final visibleTeams = LaegetaskerAccessLogic.visibleTeams(
      teams: _teams,
      teamLocked: _teamLocked,
      assignedTeams: _assignedTeams,
    );
    final teamsWithMedicalBag = visibleTeams
        .where((team) => team.needsMedicalBag)
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Lægetasker')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              user?.email == null
                  ? 'Ikke logget ind'
                  : 'Logget ind som: ${user!.email}',
            ),
            const SizedBox(height: 12),
            const SizedBox(height: 12),
            Expanded(
              child: teamsWithMedicalBag.isEmpty
                  ? const Center(
                      child: Text(
                        'Ingen hold er markeret med behov for lægetaske. Sæt det på holdet under Hold.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.builder(
                      itemCount: teamsWithMedicalBag.length,
                      itemBuilder: (context, index) {
                        final team = teamsWithMedicalBag[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ExpansionTile(
                            title: Text(team.name),
                            subtitle: Text('Rapportfrekvens: $cadenceLabel'),
                            childrenPadding: const EdgeInsets.fromLTRB(
                              12,
                              0,
                              12,
                              12,
                            ),
                            children: [
                              StreamBuilder<
                                QuerySnapshot<Map<String, dynamic>>
                              >(
                                stream: _firestore
                                    .collection('bag_shortages')
                                    .where('teamId', isEqualTo: team.id)
                                    .where('status', isEqualTo: 'open')
                                    .snapshots(),
                                builder: (context, shortageSnapshot) {
                                  final shortageDocs =
                                      shortageSnapshot.data?.docs ?? [];
                                  final activeCaseByMaterial = <String, bool>{};
                                  for (final doc in shortageDocs) {
                                    final data = doc.data();
                                    final materialId =
                                        data['materialId'] as String?;
                                    if (materialId == null) continue;
                                    activeCaseByMaterial[materialId] = true;
                                  }

                                  final medKeys = <String>{
                                    ...team.holdings.keys,
                                    ...team.expectedHoldings.keys,
                                  };
                                  final medEntries = medKeys.where((
                                    materialId,
                                  ) {
                                    final material = _materialForId(materialId);
                                    final category = material.category
                                        .toLowerCase();
                                    return category.contains('læge') ||
                                        category.contains('laege');
                                  }).toList();

                                  medEntries.sort((a, b) {
                                    final aName = _materialLabel(
                                      _materialForId(a),
                                    );
                                    final bName = _materialLabel(
                                      _materialForId(b),
                                    );
                                    return aName.toLowerCase().compareTo(
                                      bName.toLowerCase(),
                                    );
                                  });

                                  if (medEntries.isEmpty) {
                                    return const Padding(
                                      padding: EdgeInsets.only(bottom: 8),
                                      child: Text(
                                        'Ingen lægetaske-materialer fundet på dette hold.',
                                      ),
                                    );
                                  }

                                  return Column(
                                    children: [
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            Chip(
                                              label: Text(
                                                'Åbne mangler: ${shortageDocs.length}',
                                              ),
                                            ),
                                            ElevatedButton.icon(
                                              onPressed: () =>
                                                  _submitStatusReport(team),
                                              icon: const Icon(
                                                Icons.assignment_turned_in,
                                              ),
                                              label: const Text(
                                                'Indsend status',
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      for (final materialId in medEntries)
                                        Builder(
                                          builder: (context) {
                                            final material = _materialForId(
                                              materialId,
                                            );
                                            final label = _materialLabel(
                                              material,
                                            );
                                            final actual =
                                                teamActualMaterialCount(
                                                  team,
                                                  materialId,
                                                );
                                            final expected =
                                                teamExpectedMaterialCount(
                                                  team,
                                                  materialId,
                                                );
                                            final expectedMissing =
                                                expected == null
                                                ? null
                                                : teamMissingMaterialCount(
                                                    team,
                                                    materialId,
                                                  );
                                            final hasActiveCase =
                                                activeCaseByMaterial[materialId] ==
                                                true;

                                            return Card(
                                              margin:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 6,
                                                  ),
                                              child: ListTile(
                                                title: Text(label),
                                                subtitle: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      'Status: $actual ${material.unit}',
                                                    ),
                                                    if (expected != null)
                                                      Text(
                                                        'Forventet: $expected · Mangler ift. forventet: $expectedMissing',
                                                      ),
                                                    Text(
                                                      hasActiveCase
                                                          ? 'Aktiv sag: Ja'
                                                          : 'Aktiv sag: Nej',
                                                    ),
                                                  ],
                                                ),
                                                trailing: ElevatedButton(
                                                  onPressed: () =>
                                                      _reportShortage(
                                                        team: team,
                                                        material: material,
                                                        currentQty: actual,
                                                      ),
                                                  child: const Text(
                                                    'Opret/opdater sag',
                                                  ),
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
