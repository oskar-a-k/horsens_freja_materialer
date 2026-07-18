import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/material_model.dart';
import '../models/team_model.dart';
import '../services/inventory_service.dart';

class LaegetaskerPage extends StatefulWidget {
  final InventoryService service;

  const LaegetaskerPage({super.key, required this.service});

  @override
  State<LaegetaskerPage> createState() => _LaegetaskerPageState();
}

class _LaegetaskerPageState extends State<LaegetaskerPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<TeamModel> _teams = [];
  List<MaterialModel> _materials = [];
  TeamModel? _assignedTeam;
  bool _loading = true;
  String? _error;
  String _reportingCadence = 'every_2_weeks';
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

      TeamModel? initialTeam;
      final user = FirebaseAuth.instance.currentUser;

      if (user != null) {
        final userDoc = await _firestore
            .collection('users')
            .doc(user.uid)
            .get();
        final userData = userDoc.data();

        final cadence = userData?['reportingCadence'] as String?;
        if (cadence != null && cadence.isNotEmpty) {
          _reportingCadence = cadence;
        }

        final userTeamId = userData?['teamId'] as String?;
        final userTeamName = userData?['teamName'] as String?;

        if (userTeamId != null && userTeamId.isNotEmpty) {
          for (final team in teams) {
            if (team.id == userTeamId) {
              initialTeam = team;
              break;
            }
          }
        }

        if (initialTeam == null &&
            userTeamName != null &&
            userTeamName.isNotEmpty) {
          for (final team in teams) {
            if (team.name.toLowerCase() == userTeamName.toLowerCase()) {
              initialTeam = team;
              break;
            }
          }
        }

        if (initialTeam == null) {
          for (final team in teams) {
            if (team.coachId == user.uid) {
              initialTeam = team;
              break;
            }
          }
        }

        _teamLocked = initialTeam != null;
      }

      initialTeam ??= _assignedTeam;
      if (initialTeam == null && teams.length == 1) {
        initialTeam = teams.first;
      }

      if (!mounted) return;
      setState(() {
        _teams = teams;
        _materials = materials;
        _assignedTeam = initialTeam;
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
                await _firestore.collection('bag_shortages').add({
                  'teamId': team.id,
                  'teamName': team.name,
                  'materialId': material.id,
                  'materialName': _materialLabel(material),
                  'quantity': qty,
                  'note': reason,
                  'reportedByUid': user?.uid,
                  'reportedByEmail': user?.email,
                  'createdAt': FieldValue.serverTimestamp(),
                  'status': 'open',
                });

                if (!mounted) return;
                messenger.showSnackBar(
                  const SnackBar(content: Text('Mangel er registreret.')),
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
        : 'Hver 2. uge';
    final visibleTeams = _teamLocked && _assignedTeam != null
        ? [
            for (final t in _teams)
              if (t.id == _assignedTeam!.id) t,
          ]
        : _teams;

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
              child: visibleTeams.isEmpty
                  ? const Center(
                      child: Text(
                        'Ingen hold fundet. Hvis en træner kun skal se eget hold, tilknyt teamId eller teamName på bruger i users-samlingen.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.builder(
                      itemCount: visibleTeams.length,
                      itemBuilder: (context, index) {
                        final team = visibleTeams[index];
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
                                  final shortageByMaterial = <String, int>{};
                                  for (final doc in shortageDocs) {
                                    final data = doc.data();
                                    final materialId =
                                        data['materialId'] as String?;
                                    final quantity =
                                        (data['quantity'] as num?)?.toInt() ??
                                        0;
                                    if (materialId == null) continue;
                                    shortageByMaterial[materialId] =
                                        (shortageByMaterial[materialId] ?? 0) +
                                        quantity;
                                  }

                                  final entries = team.holdings.entries
                                      .toList();
                                  final medEntries = entries.where((entry) {
                                    final material = _materialForId(entry.key);
                                    final category = material.category
                                        .toLowerCase();
                                    return category.contains('læge') ||
                                        category.contains('laege');
                                  }).toList();

                                  medEntries.sort((a, b) {
                                    final aName = _materialLabel(
                                      _materialForId(a.key),
                                    );
                                    final bName = _materialLabel(
                                      _materialForId(b.key),
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
                                      for (final entry in medEntries)
                                        Builder(
                                          builder: (context) {
                                            final material = _materialForId(
                                              entry.key,
                                            );
                                            final label = _materialLabel(
                                              material,
                                            );
                                            final actual = entry.value;
                                            final expected = team
                                                .expectedHoldings[entry.key];
                                            final expectedMissing =
                                                expected == null
                                                ? null
                                                : expected - actual;
                                            final reportedMissing =
                                                shortageByMaterial[entry.key] ??
                                                0;

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
                                                      'Meldte mangler (åbne): $reportedMissing',
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
                                                    'Meld mangel',
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
