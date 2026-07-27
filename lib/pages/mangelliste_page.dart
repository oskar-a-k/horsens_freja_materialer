import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/team_model.dart';
import '../services/shortage_case_logic.dart';
import '../services/shortage_case_service.dart';

class MangellistePage extends StatefulWidget {
  const MangellistePage({super.key});

  @override
  State<MangellistePage> createState() => _MangellistePageState();
}

class _MangellistePageState extends State<MangellistePage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late final ShortageCaseService _shortageCaseService = ShortageCaseService(
    firestore: _firestore,
  );

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

  Future<void> _applySelfRefillToTeam({
    required String teamId,
    required String materialId,
    required int quantityHint,
  }) async {
    if (teamId.trim().isEmpty || materialId.trim().isEmpty) {
      throw StateError('Mangler holdId eller materialeId på mangelsagen.');
    }

    final teamRef = _firestore.collection('teams').doc(teamId);

    await _firestore.runTransaction((transaction) async {
      final teamSnapshot = await transaction.get(teamRef);
      if (!teamSnapshot.exists) {
        throw StateError('Holdet findes ikke længere.');
      }

      final teamData = teamSnapshot.data() ?? <String, dynamic>{};
      final holdings = Map<String, dynamic>.from(
        teamData['holdings'] as Map<String, dynamic>? ??
            const <String, dynamic>{},
      );
      final expected = Map<String, dynamic>.from(
        teamData['expectedHoldings'] as Map<String, dynamic>? ??
            const <String, dynamic>{},
      );

      final currentActual = (holdings[materialId] as num?)?.toInt() ?? 0;
      final expectedValue = (expected[materialId] as num?)?.toInt();

      final target =
          expectedValue ??
          currentActual + (quantityHint > 0 ? quantityHint : 0);

      if (target <= 0) {
        holdings.remove(materialId);
      } else {
        holdings[materialId] = target;
      }

      transaction.update(teamRef, {
        'holdings': holdings,
        'updatedAt': DateTime.now().toIso8601String(),
      });
    });
  }

  Future<void> _closeAsSelfRefilled({
    required Iterable<String> docIds,
    required String teamId,
    required String materialId,
    required int quantityHint,
  }) async {
    await _applySelfRefillToTeam(
      teamId: teamId,
      materialId: materialId,
      quantityHint: quantityHint,
    );

    final user = FirebaseAuth.instance.currentUser;
    await _shortageCaseService.closeCases(
      docIds: docIds,
      resolutionFields: {
        'status': 'closed',
        'resolutionType': 'self_refilled',
        'resolvedAt': FieldValue.serverTimestamp(),
        'resolvedByUid': user?.uid,
        'resolvedByEmail': user?.email,
      },
    );
  }

  Future<void> _closeAsDelivered({
    required Iterable<String> docIds,
    required String teamId,
    required String materialId,
    required int quantityHint,
    required DateTime deliveredDate,
  }) async {
    await _applySelfRefillToTeam(
      teamId: teamId,
      materialId: materialId,
      quantityHint: quantityHint,
    );

    final user = FirebaseAuth.instance.currentUser;
    final dateOnly = DateTime(
      deliveredDate.year,
      deliveredDate.month,
      deliveredDate.day,
    );

    await _shortageCaseService.closeCases(
      docIds: docIds,
      resolutionFields: {
        'status': 'closed',
        'resolutionType': 'delivered',
        'deliveredAt': Timestamp.fromDate(dateOnly),
        'resolvedAt': FieldValue.serverTimestamp(),
        'resolvedByUid': user?.uid,
        'resolvedByEmail': user?.email,
      },
    );
  }

  Future<void> _showDeliveredDialog(
    Iterable<String> docIds, {
    required String teamId,
    required String materialId,
    required int quantityHint,
  }) async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      helpText: 'Vælg udleveringsdato',
    );
    if (selected == null) return;

    try {
      await _closeAsDelivered(
        docIds: docIds,
        teamId: teamId,
        materialId: materialId,
        quantityHint: quantityHint,
        deliveredDate: selected,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mangel lukket: Vare udleveret. Beholdning opdateret.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Kunne ikke opdatere beholdning/lukke sag ved udlevering: $e',
          ),
        ),
      );
    }
  }

  Future<void> _closeAsResolvedByStatus(Iterable<String> docIds) async {
    final user = FirebaseAuth.instance.currentUser;
    await _shortageCaseService.closeCases(
      docIds: docIds,
      resolutionFields: {
        'status': 'closed',
        'resolutionType': 'resolved_by_status',
        'resolvedAt': FieldValue.serverTimestamp(),
        'resolvedByUid': user?.uid,
        'resolvedByEmail': user?.email,
      },
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
                await _shortageCaseService.upsertOpenCase(
                  teamId: teamId,
                  teamName: teamName,
                  materialId: materialId,
                  materialName: materialName,
                  reportedQuantity: qty,
                  note: note,
                  source: 'auto_gap',
                  reportedByUid: user?.uid,
                  reportedByEmail: user?.email,
                );

                if (!mounted) return;
                messenger.showSnackBar(
                  const SnackBar(content: Text('Sag er oprettet/opdateret.')),
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

  Widget _buildReportedShortageCard(_OpenShortageCase openCase) {
    final resolvedByStatusCandidate =
        ShortageCaseLogic.isResolvedByStatusCandidate(openCase.currentMissing);
    final sourceLabel = switch (openCase.source) {
      'coach_report' => 'Kilde: Trænerindmelding',
      'auto_gap' => 'Kilde: Oprettet fra beregnet mangel',
      'admin_created' => 'Kilde: Oprettet af admin',
      _ => 'Kilde: Ukendt',
    };

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              openCase.materialName,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text('Hold: ${openCase.teamName}'),
            Text('Sagsantal: ${openCase.reportedQuantity}'),
            Text('Aktuel beregnet mangel: ${openCase.currentMissing}'),
            if (resolvedByStatusCandidate)
              Text(
                'Status ser nu korrekt ud. Sagen kan lukkes som løst af statusændring.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            Text(sourceLabel),
            Text('Indmeldt af: ${openCase.reportedByEmail}'),
            Text('Indmeldt: ${_dateLabel(openCase.createdAt)}'),
            if (openCase.note.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Note: ${openCase.note}'),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (resolvedByStatusCandidate)
                  FilledButton.tonal(
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await _closeAsResolvedByStatus(openCase.docIds);
                      if (!mounted) return;
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text('Sag lukket: Løst af statusændring.'),
                        ),
                      );
                    },
                    child: const Text('Luk som status rettet'),
                  ),
                OutlinedButton(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    try {
                      await _closeAsSelfRefilled(
                        docIds: openCase.docIds,
                        teamId: openCase.teamId,
                        materialId: openCase.materialId,
                        quantityHint: openCase.currentMissing > 0
                            ? openCase.currentMissing
                            : openCase.reportedQuantity,
                      );
                      if (!mounted) return;
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Mangel lukket: Fyldt på taske selv. Beholdning opdateret.',
                          ),
                        ),
                      );
                    } catch (e) {
                      if (!mounted) return;
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            'Kunne ikke opdatere beholdning/lukke sag: $e',
                          ),
                        ),
                      );
                    }
                  },
                  child: const Text('Fyldt på taske selv'),
                ),
                ElevatedButton(
                  onPressed: () => _showDeliveredDialog(
                    openCase.docIds,
                    teamId: openCase.teamId,
                    materialId: openCase.materialId,
                    quantityHint: openCase.currentMissing > 0
                        ? openCase.currentMissing
                        : openCase.reportedQuantity,
                  ),
                  child: const Text('Vare udleveret'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalculatedGapCard(Map<String, dynamic> gap) {
    final hasActiveCase = gap['hasActiveCase'] as bool;
    final activeCaseQuantity = gap['activeCaseQuantity'] as int;

    return Card(
      color: Colors.orange.shade50,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              gap['materialName'] as String,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text('Hold: ${gap['teamName']}'),
            Text('Forventet beholdning: ${gap['expected']}'),
            Text('Aktuel status: ${gap['actual']}'),
            Text(
              'Beregnet mangel: ${gap['missing']}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              hasActiveCase
                  ? 'Aktiv sag: Ja ($activeCaseQuantity registreret)'
                  : 'Aktiv sag: Nej',
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: !hasActiveCase
                  ? () => _createShortageFromAutoGap(
                      teamId: gap['teamId'] as String,
                      teamName: gap['teamName'] as String,
                      materialId: gap['materialId'] as String,
                      materialName: gap['materialName'] as String,
                      suggestedQty: gap['missing'] as int,
                    )
                  : null,
              icon: const Icon(Icons.add_task),
              label: Text(!hasActiveCase ? 'Opret sag' : 'Sag findes allerede'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOpenSection({
    required String title,
    required String description,
    required List<Map<String, dynamic>> calculatedGaps,
    required List<_OpenShortageCase> activeCases,
  }) {
    final unresolvedCases = activeCases
        .where(
          (openCase) => !ShortageCaseLogic.isResolvedByStatusCandidate(
            openCase.currentMissing,
          ),
        )
        .toList();
    final resolvedByStatusCases = activeCases
        .where(
          (openCase) => ShortageCaseLogic.isResolvedByStatusCandidate(
            openCase.currentMissing,
          ),
        )
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            description,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        if (calculatedGaps.isEmpty && activeCases.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text('Ingen åbne poster i denne gruppe.'),
          ),
        if (calculatedGaps.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'Beregnet mangel',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          ...calculatedGaps.map(_buildCalculatedGapCard),
        ],
        if (unresolvedCases.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Aktive sager',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          ...unresolvedCases.map(_buildReportedShortageCard),
        ],
        if (resolvedByStatusCases.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Sager uden aktuel mangel',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              'Disse sager har ikke længere en beregnet mangel og kan normalt lukkes som løst af statusændring.',
            ),
          ),
          ...resolvedByStatusCases.map(_buildReportedShortageCard),
        ],
      ],
    );
  }

  Map<String, _OpenShortageCase> _buildOpenCaseMap(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final records = <ShortageCaseRecord>[];
    for (final doc in docs) {
      final data = doc.data();
      final teamId = data['teamId'] as String?;
      final materialId = data['materialId'] as String?;
      if (teamId == null || materialId == null) continue;
      final createdAt = data['createdAt'] as Timestamp?;
      records.add(
        ShortageCaseRecord(
          docId: doc.id,
          teamId: teamId,
          teamName: data['teamName'] as String? ?? 'Ukendt hold',
          materialId: materialId,
          materialName: data['materialName'] as String? ?? 'Ukendt vare',
          reportedQuantity:
              (data['reportedQuantity'] as num?)?.toInt() ??
              (data['quantity'] as num?)?.toInt() ??
              0,
          note: (data['note'] as String? ?? '').trim(),
          source: data['source'] as String? ?? 'unknown',
          reportedByEmail: data['reportedByEmail'] as String? ?? 'ukendt',
          createdAtMillis: createdAt?.millisecondsSinceEpoch ?? 0,
        ),
      );
    }

    final result = <String, _OpenShortageCase>{};
    final grouped = ShortageCaseLogic.groupOpenCases(records);
    for (final entry in grouped.entries) {
      final groupedCase = entry.value;
      result[entry.key] = _OpenShortageCase(
        key: entry.key,
        docIds: groupedCase.docIds,
        teamId: groupedCase.teamId,
        teamName: groupedCase.teamName,
        materialId: groupedCase.materialId,
        materialName: groupedCase.materialName,
        reportedQuantity: groupedCase.reportedQuantity,
        note: groupedCase.note,
        source: groupedCase.source,
        reportedByEmail: groupedCase.reportedByEmail,
        createdAt: groupedCase.createdAtMillis == 0
            ? null
            : Timestamp.fromMillisecondsSinceEpoch(groupedCase.createdAtMillis),
      );
    }
    return result;
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

                final shortageDocs =
                    <QueryDocumentSnapshot<Map<String, dynamic>>>[
                      ...(shortageSnapshot.data?.docs ??
                          const <
                            QueryDocumentSnapshot<Map<String, dynamic>>
                          >[]),
                    ]..sort((a, b) {
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

                final openCasesByKey = _buildOpenCaseMap(shortageDocs);

                final expectedGaps = <Map<String, dynamic>>[];
                for (final teamDoc in teams) {
                  final teamData = teamDoc.data();
                  final teamId = teamDoc.id;
                  final teamName = teamData['name'] as String? ?? 'Ukendt hold';
                  for (final materialId in teamMaterialIdsFromMap(teamData)) {
                    final expected = teamExpectedMaterialCountFromMap(
                      teamData,
                      materialId,
                    );
                    if (expected == null) continue;
                    final actual = teamActualMaterialCountFromMap(
                      teamData,
                      materialId,
                    );
                    final missing = ShortageCaseLogic.calculatedMissing(
                      expected: expected,
                      actual: actual,
                    );
                    if (missing <= 0) continue;

                    final caseKey = ShortageCaseService.keyFor(
                      teamId,
                      materialId,
                    );
                    final activeCase = openCasesByKey[caseKey];
                    if (activeCase != null) {
                      activeCase.currentMissing = missing;
                    }

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
                      'hasActiveCase': activeCase != null,
                      'activeCaseQuantity': activeCase?.reportedQuantity ?? 0,
                      'activeCaseDocIds':
                          activeCase?.docIds ?? const <String>[],
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

                final consumableReported = <_OpenShortageCase>[];
                final otherReported = <_OpenShortageCase>[];
                for (final openCase in openCasesByKey.values) {
                  final materialId = openCase.materialId;
                  final material = materialById[materialId];
                  final isConsumable = _isConsumableCategory(
                    material?['category'] as String?,
                  );
                  if (isConsumable) {
                    consumableReported.add(openCase);
                  } else {
                    otherReported.add(openCase);
                  }
                }

                return ListView(
                  children: [
                    _buildOpenSection(
                      title: 'Forbrugsvarer (lægetaske) - prioriteret',
                      description:
                          'Her vises den beregnede afvigelse mellem forventet beholdning og faktisk status samt eventuelle aktive sager.',
                      calculatedGaps: consumableAuto,
                      activeCases: consumableReported,
                    ),
                    _buildOpenSection(
                      title: 'Ovrige mangler (kan vare over flere uger)',
                      description:
                          'Her vises længerevarende mangler som fx bolde og andet udstyr, adskilt fra de hurtige forbrugssager.',
                      calculatedGaps: otherAuto,
                      activeCases: otherReported,
                    ),
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
            final teamId = data['teamId'] as String? ?? '';
            final materialName =
                data['materialName'] as String? ?? 'Ukendt vare';
            final materialId = data['materialId'] as String? ?? '';
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
                            : resolutionType == 'resolved_by_status'
                            ? 'Lukket som: Løst af statusændring'
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
                              if (teamId.isEmpty || materialId.isEmpty) {
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Kan ikke lukke sagen: mangler hold/materiale reference.',
                                    ),
                                  ),
                                );
                                return;
                              }
                              try {
                                await _closeAsSelfRefilled(
                                  docIds: [doc.id],
                                  teamId: teamId,
                                  materialId: materialId,
                                  quantityHint: qty,
                                );
                                if (!mounted) return;
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Mangel lukket: Fyldt på taske selv. Beholdning opdateret.',
                                    ),
                                  ),
                                );
                              } catch (e) {
                                if (!mounted) return;
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Kunne ikke opdatere beholdning/lukke sag: $e',
                                    ),
                                  ),
                                );
                              }
                            },
                            child: const Text('Fyldt på taske selv'),
                          ),
                          ElevatedButton(
                            onPressed: teamId.isEmpty || materialId.isEmpty
                                ? null
                                : () => _showDeliveredDialog(
                                    [doc.id],
                                    teamId: teamId,
                                    materialId: materialId,
                                    quantityHint: qty,
                                  ),
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

class _OpenShortageCase {
  final String key;
  final List<String> docIds;
  final String teamId;
  final String teamName;
  final String materialId;
  final String materialName;
  final int reportedQuantity;
  final String note;
  final String source;
  final String reportedByEmail;
  final Timestamp? createdAt;
  int currentMissing = 0;

  _OpenShortageCase({
    required this.key,
    required this.docIds,
    required this.teamId,
    required this.teamName,
    required this.materialId,
    required this.materialName,
    required this.reportedQuantity,
    required this.note,
    required this.source,
    required this.reportedByEmail,
    required this.createdAt,
  });
}
