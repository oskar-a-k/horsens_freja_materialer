import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class MangellistePage extends StatefulWidget {
  const MangellistePage({super.key});

  @override
  State<MangellistePage> createState() => _MangellistePageState();
}

class _MangellistePageState extends State<MangellistePage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _friendlyErrorMessage(Object error) {
    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
          return 'Du har ikke adgang til at se mangellisten.';
        case 'unavailable':
          return 'Forbindelse til databasen fejlede. Prøv igen om et øjeblik.';
        case 'failed-precondition':
          return 'Mangellisten kræver en database-indstilling (ofte et Firestore index).';
        default:
          return 'Der opstod en fejl ved indlæsning af mangellisten.';
      }
    }
    return 'Der opstod en fejl ved indlæsning af mangellisten.';
  }

  String _dateLabel(Timestamp? ts) {
    if (ts == null) return '-';
    final d = ts.toDate();
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  Future<void> _closeAsSelfRefilled(String docId) async {
    final user = FirebaseAuth.instance.currentUser;
    await _firestore.collection('bag_shortages').doc(docId).update({
      'status': 'closed',
      'resolutionType': 'self_refilled',
      'resolvedAt': FieldValue.serverTimestamp(),
      'resolvedByUid': user?.uid,
      'resolvedByEmail': user?.email,
    });
  }

  Future<void> _closeAsDelivered({
    required String docId,
    required DateTime deliveredDate,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final dateOnly = DateTime(
      deliveredDate.year,
      deliveredDate.month,
      deliveredDate.day,
    );

    await _firestore.collection('bag_shortages').doc(docId).update({
      'status': 'closed',
      'resolutionType': 'delivered',
      'deliveredAt': Timestamp.fromDate(dateOnly),
      'resolvedAt': FieldValue.serverTimestamp(),
      'resolvedByUid': user?.uid,
      'resolvedByEmail': user?.email,
    });
  }

  Future<void> _showDeliveredDialog(String docId) async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      helpText: 'Vælg udleveringsdato',
    );
    if (selected == null) return;

    await _closeAsDelivered(docId: docId, deliveredDate: selected);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Mangel lukket: Vare udleveret.')),
    );
  }

  Future<void> _createShortageFromAutoGap({
    required String teamId,
    required String teamName,
    required String materialId,
    required String materialName,
    required int suggestedQty,
  }) async {
    final qtyCtrl = TextEditingController(text: suggestedQty.toString());
    final noteCtrl = TextEditingController(
      text: 'Automatisk mangel fra forventet vs. status',
    );

    await showDialog<void>(
      context: context,
      builder: (context) {
        final dialogNavigator = Navigator.of(context);
        final messenger = ScaffoldMessenger.of(context);
        return AlertDialog(
          title: const Text('Indmeld automatisk mangel'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(materialName),
              const SizedBox(height: 6),
              Text('Hold: $teamName'),
              const SizedBox(height: 12),
              TextField(
                controller: qtyCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Antal'),
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
                final note = noteCtrl.text.trim();
                if (qty <= 0) {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Antal skal være over 0.')),
                  );
                  return;
                }
                if (note.isEmpty) {
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Skriv begrundelse for manglen.'),
                    ),
                  );
                  return;
                }

                final user = FirebaseAuth.instance.currentUser;
                await _firestore.collection('bag_shortages').add({
                  'teamId': teamId,
                  'teamName': teamName,
                  'materialId': materialId,
                  'materialName': materialName,
                  'quantity': qty,
                  'note': note,
                  'reportedByUid': user?.uid,
                  'reportedByEmail': user?.email,
                  'createdAt': FieldValue.serverTimestamp(),
                  'status': 'open',
                });

                if (!mounted) return;
                messenger.showSnackBar(
                  const SnackBar(content: Text('Mangel er indmeldt.')),
                );
                dialogNavigator.pop();
              },
              child: const Text('Indmeld'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildErrorCard(Object error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _friendlyErrorMessage(error),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Vis tekniske detaljer'),
                  children: [SelectableText(error.toString())],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _materialLabelFromMap(Map<String, dynamic> data) {
    final name = data['name'] as String? ?? 'Ukendt vare';
    final variant = (data['variant'] as String? ?? '').trim();
    if (variant.isEmpty) return name;
    return '$name · $variant';
  }

  bool _isConsumableCategory(String? category) {
    final c = (category ?? '').toLowerCase();
    return c.contains('læge') ||
        c.contains('laege') ||
        c.contains('forbrug') ||
        c.contains('consum');
  }

  Widget _buildReportedShortageCard(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final teamName = data['teamName'] as String? ?? 'Ukendt hold';
    final materialName = data['materialName'] as String? ?? 'Ukendt vare';
    final qty = (data['quantity'] as num?)?.toInt() ?? 0;
    final note = (data['note'] as String? ?? '').trim();
    final reporter = data['reportedByEmail'] as String? ?? 'ukendt';
    final createdAt = data['createdAt'] as Timestamp?;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              materialName,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text('Hold: $teamName'),
            Text('Antal: $qty'),
            Text('Indmeldt af: $reporter'),
            Text('Indmeldt: ${_dateLabel(createdAt)}'),
            if (note.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Note: $note'),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    await _closeAsSelfRefilled(doc.id);
                    if (!mounted) return;
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Mangel lukket: Fyldt på taske selv.'),
                      ),
                    );
                  },
                  child: const Text('Fyldt på taske selv'),
                ),
                ElevatedButton(
                  onPressed: () => _showDeliveredDialog(doc.id),
                  child: const Text('Vare udleveret'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOpenShortagesTab() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _firestore
          .collection('bag_shortages')
          .where('status', isEqualTo: 'open')
          .snapshots(),
      builder: (context, shortageSnapshot) {
        if (shortageSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (shortageSnapshot.hasError) {
          return _buildErrorCard(shortageSnapshot.error!);
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _firestore.collection('teams').snapshots(),
          builder: (context, teamsSnapshot) {
            if (teamsSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (teamsSnapshot.hasError) {
              return _buildErrorCard(teamsSnapshot.error!);
            }

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _firestore.collection('materials').snapshots(),
              builder: (context, materialsSnapshot) {
                if (materialsSnapshot.connectionState ==
                    ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (materialsSnapshot.hasError) {
                  return _buildErrorCard(materialsSnapshot.error!);
                }

                final shortageDocs = [...(shortageSnapshot.data?.docs ?? [])]
                  ..sort((a, b) {
                    final aTs = a.data()['createdAt'] as Timestamp?;
                    final bTs = b.data()['createdAt'] as Timestamp?;
                    final aMillis = aTs?.millisecondsSinceEpoch ?? 0;
                    final bMillis = bTs?.millisecondsSinceEpoch ?? 0;
                    return bMillis.compareTo(aMillis);
                  });

                final teams = teamsSnapshot.data?.docs ?? [];
                final materials = materialsSnapshot.data?.docs ?? [];
                final materialById = <String, Map<String, dynamic>>{};
                for (final doc in materials) {
                  materialById[doc.id] = doc.data();
                }

                final reportedByTeamMaterial = <String, int>{};
                for (final doc in shortageDocs) {
                  final data = doc.data();
                  final teamId = data['teamId'] as String?;
                  final materialId = data['materialId'] as String?;
                  final qty = (data['quantity'] as num?)?.toInt() ?? 0;
                  if (teamId == null || materialId == null) continue;
                  final key = '$teamId::$materialId';
                  reportedByTeamMaterial[key] =
                      (reportedByTeamMaterial[key] ?? 0) + qty;
                }

                final expectedGaps = <Map<String, dynamic>>[];
                for (final teamDoc in teams) {
                  final teamData = teamDoc.data();
                  final teamId = teamDoc.id;
                  final teamName = teamData['name'] as String? ?? 'Ukendt hold';
                  final holdingsRaw =
                      teamData['holdings'] as Map<String, dynamic>? ?? {};
                  final expectedRaw =
                      teamData['expectedHoldings'] as Map<String, dynamic>? ??
                      {};

                  for (final entry in expectedRaw.entries) {
                    final materialId = entry.key;
                    final expected = (entry.value as num?)?.toInt() ?? 0;
                    final actual =
                        (holdingsRaw[materialId] as num?)?.toInt() ?? 0;
                    final missing = expected - actual;
                    if (missing <= 0) continue;

                    final reportedKey = '$teamId::$materialId';
                    final reportedMissing =
                        reportedByTeamMaterial[reportedKey] ?? 0;
                    final remainingToReport = missing - reportedMissing;

                    final material = materialById[materialId];
                    final materialLabel = material == null
                        ? 'Ukendt vare'
                        : _materialLabelFromMap(material);

                    expectedGaps.add({
                      'teamId': teamId,
                      'teamName': teamName,
                      'materialId': materialId,
                      'materialName': materialLabel,
                      'expected': expected,
                      'actual': actual,
                      'missing': missing,
                      'reportedMissing': reportedMissing,
                      'remainingToReport': remainingToReport,
                      'isConsumable': _isConsumableCategory(
                        material?['category'] as String?,
                      ),
                    });
                  }
                }

                expectedGaps.sort((a, b) {
                  final teamCmp = (a['teamName'] as String)
                      .toLowerCase()
                      .compareTo((b['teamName'] as String).toLowerCase());
                  if (teamCmp != 0) return teamCmp;
                  return (a['materialName'] as String).toLowerCase().compareTo(
                    (b['materialName'] as String).toLowerCase(),
                  );
                });

                if (shortageDocs.isEmpty && expectedGaps.isEmpty) {
                  return const Center(child: Text('Ingen åbne mangler.'));
                }

                final consumableAuto = expectedGaps
                    .where((g) => g['isConsumable'] == true)
                    .toList();
                final otherAuto = expectedGaps
                    .where((g) => g['isConsumable'] != true)
                    .toList();

                final consumableReported =
                    <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                final otherReported =
                    <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                for (final doc in shortageDocs) {
                  final data = doc.data();
                  final materialId = data['materialId'] as String?;
                  final material = materialId == null
                      ? null
                      : materialById[materialId];
                  final isConsumable = _isConsumableCategory(
                    material?['category'] as String?,
                  );
                  if (isConsumable) {
                    consumableReported.add(doc);
                  } else {
                    otherReported.add(doc);
                  }
                }

                return ListView(
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Text(
                        'Forbrugsvarer (lægetaske) - prioriteret',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (consumableAuto.isEmpty && consumableReported.isEmpty)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Text('Ingen åbne forbrugsvare-mangler.'),
                      ),
                    if (consumableAuto.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Text(
                          'Automatiske mangler (forventet > status)',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      ...consumableAuto.map((gap) {
                        return Card(
                          color: Colors.orange.shade50,
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  gap['materialName'] as String,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text('Hold: ${gap['teamName']}'),
                                Text('Forventet: ${gap['expected']}'),
                                Text('Status: ${gap['actual']}'),
                                Text(
                                  'Mangler: ${gap['missing']}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  'Indmeldt allerede: ${gap['reportedMissing']}',
                                ),
                                const SizedBox(height: 8),
                                ElevatedButton.icon(
                                  onPressed:
                                      (gap['remainingToReport'] as int) > 0
                                      ? () => _createShortageFromAutoGap(
                                          teamId: gap['teamId'] as String,
                                          teamName: gap['teamName'] as String,
                                          materialId:
                                              gap['materialId'] as String,
                                          materialName:
                                              gap['materialName'] as String,
                                          suggestedQty:
                                              gap['remainingToReport'] as int,
                                        )
                                      : null,
                                  icon: const Icon(Icons.add_task),
                                  label: Text(
                                    (gap['remainingToReport'] as int) > 0
                                        ? 'Indmeld mangel (${gap['remainingToReport']})'
                                        : 'Allerede fuldt indmeldt',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                    if (consumableReported.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Text(
                          'Indmeldte mangler',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      ...consumableReported.map(_buildReportedShortageCard),
                    ],
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Text(
                        'Ovrige mangler (kan vare over flere uger)',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (otherAuto.isEmpty && otherReported.isEmpty)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Text('Ingen ovrige åbne mangler.'),
                      ),
                    if (otherAuto.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Text(
                          'Automatiske mangler (forventet > status)',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      ...otherAuto.map((gap) {
                        return Card(
                          color: Colors.orange.shade50,
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  gap['materialName'] as String,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text('Hold: ${gap['teamName']}'),
                                Text('Forventet: ${gap['expected']}'),
                                Text('Status: ${gap['actual']}'),
                                Text(
                                  'Mangler: ${gap['missing']}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  'Indmeldt allerede: ${gap['reportedMissing']}',
                                ),
                                const SizedBox(height: 8),
                                ElevatedButton.icon(
                                  onPressed:
                                      (gap['remainingToReport'] as int) > 0
                                      ? () => _createShortageFromAutoGap(
                                          teamId: gap['teamId'] as String,
                                          teamName: gap['teamName'] as String,
                                          materialId:
                                              gap['materialId'] as String,
                                          materialName:
                                              gap['materialName'] as String,
                                          suggestedQty:
                                              gap['remainingToReport'] as int,
                                        )
                                      : null,
                                  icon: const Icon(Icons.add_task),
                                  label: Text(
                                    (gap['remainingToReport'] as int) > 0
                                        ? 'Indmeld mangel (${gap['remainingToReport']})'
                                        : 'Allerede fuldt indmeldt',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                    if (otherReported.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Text(
                          'Indmeldte mangler',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      ...otherReported.map(_buildReportedShortageCard),
                    ],
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildShortagesTab({required bool closed}) {
    if (!closed) {
      return _buildOpenShortagesTab();
    }

    final status = closed ? 'closed' : 'open';

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _firestore
          .collection('bag_shortages')
          .where('status', isEqualTo: status)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return _buildErrorCard(snapshot.error!);
        }

        final docs = [...(snapshot.data?.docs ?? [])]
          ..sort((a, b) {
            final aData = a.data();
            final bData = b.data();

            final aTs = closed
                ? (aData['resolvedAt'] as Timestamp? ??
                      aData['createdAt'] as Timestamp?)
                : aData['createdAt'] as Timestamp?;
            final bTs = closed
                ? (bData['resolvedAt'] as Timestamp? ??
                      bData['createdAt'] as Timestamp?)
                : bData['createdAt'] as Timestamp?;

            final aMillis = aTs?.millisecondsSinceEpoch ?? 0;
            final bMillis = bTs?.millisecondsSinceEpoch ?? 0;
            return bMillis.compareTo(aMillis);
          });

        if (docs.isEmpty) {
          return Center(
            child: Text(
              closed ? 'Ingen lukkede mangler endnu.' : 'Ingen åbne mangler.',
            ),
          );
        }

        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data();
            final teamName = data['teamName'] as String? ?? 'Ukendt hold';
            final materialName =
                data['materialName'] as String? ?? 'Ukendt vare';
            final qty = (data['quantity'] as num?)?.toInt() ?? 0;
            final note = (data['note'] as String? ?? '').trim();
            final reporter = data['reportedByEmail'] as String? ?? 'ukendt';
            final createdAt = data['createdAt'] as Timestamp?;

            final resolvedBy = data['resolvedByEmail'] as String?;
            final resolvedAt = data['resolvedAt'] as Timestamp?;
            final deliveredAt = data['deliveredAt'] as Timestamp?;
            final resolutionType = data['resolutionType'] as String?;

            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      materialName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text('Hold: $teamName'),
                    Text('Antal: $qty'),
                    Text('Indmeldt af: $reporter'),
                    Text('Indmeldt: ${_dateLabel(createdAt)}'),
                    if (note.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text('Note: $note'),
                    ],
                    if (closed) ...[
                      const SizedBox(height: 8),
                      Text(
                        resolutionType == 'delivered'
                            ? 'Lukket som: Vare udleveret'
                            : 'Lukket som: Fyldt på taske selv',
                      ),
                      if (deliveredAt != null)
                        Text('Udleveret dato: ${_dateLabel(deliveredAt)}'),
                      Text('Lukket af: ${resolvedBy ?? 'ukendt'}'),
                      Text('Lukket: ${_dateLabel(resolvedAt)}'),
                    ] else ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: () async {
                              final messenger = ScaffoldMessenger.of(context);
                              await _closeAsSelfRefilled(doc.id);
                              if (!mounted) return;
                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Mangel lukket: Fyldt på taske selv.',
                                  ),
                                ),
                              );
                            },
                            child: const Text('Fyldt på taske selv'),
                          ),
                          ElevatedButton(
                            onPressed: () => _showDeliveredDialog(doc.id),
                            child: const Text('Vare udleveret'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Mangelliste'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Åbne'),
              Tab(text: 'Lukkede'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildShortagesTab(closed: false),
            _buildShortagesTab(closed: true),
          ],
        ),
      ),
    );
  }
}
