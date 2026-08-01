import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/team_model.dart';
import '../models/material_model.dart';
import '../services/inventory_service.dart';
import '../services/shortage_case_service.dart';

class HoldPage extends StatefulWidget {
  final InventoryService service;

  const HoldPage({super.key, required this.service});

  @override
  State<HoldPage> createState() => _HoldPageState();
}

class _HoldPageState extends State<HoldPage> {
  static const Set<String> _adminOverrideEmails = {
    'materialer@horsensfreja.dk',
  };

  static const Set<String> _materialManagerRoles = {
    'manager',
    'materialforvalter',
    'materialeforvalter',
    'materialeansvarlig',
  };

  late final InventoryService _service;
  List<TeamModel> _teams = [];
  String _teamSearch = '';
  bool _canManageTeamMaterials = false;
  bool _isEditingOrder = false;

  bool _canManageFromUserData(
    Map<String, dynamic>? userData, {
    required bool hasOverrideAdmin,
  }) {
    final isAdmin = userData?['isAdmin'] as bool? ?? false;
    final role = (userData?['role'] as String? ?? '').trim().toLowerCase();

    final isCoachRole =
        role == 'coach' || role == 'traener' || role == 'træner';
    if (isCoachRole) return false;

    final hasManagerRole =
        role == 'admin' || _materialManagerRoles.contains(role);

    return hasOverrideAdmin || isAdmin || hasManagerRole;
  }

  bool _isMedicalBagCategory(String category) {
    final c = category.toLowerCase();
    return c.contains('læge') || c.contains('laege');
  }

  Map<String, int> _filterMedicalTemplate(
    Map<String, int> source,
    Set<String> validMedicalIds,
  ) {
    final result = <String, int>{};
    for (final entry in source.entries) {
      final qty = entry.value;
      if (qty <= 0) continue;
      if (!validMedicalIds.contains(entry.key)) continue;
      result[entry.key] = qty;
    }
    return result;
  }

  Future<Map<String, int>> _loadMedicalBagTemplateFromSettings(
    Set<String> validMedicalIds,
  ) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('app_settings')
        .doc('medical_bag_template')
        .get();
    final data = snapshot.data();
    if (data == null) return const <String, int>{};

    final rawItems = data['items'] as Map<String, dynamic>?;
    if (rawItems == null || rawItems.isEmpty) return const <String, int>{};

    final parsed = <String, int>{};
    rawItems.forEach((key, value) {
      parsed[key] = (value as num?)?.toInt() ?? 0;
    });
    return _filterMedicalTemplate(parsed, validMedicalIds);
  }

  Future<Map<String, int>> _resolveMedicalBagTemplateForTeam(
    TeamModel team,
    Set<String> validMedicalIds,
  ) async {
    final fromSettings = await _loadMedicalBagTemplateFromSettings(
      validMedicalIds,
    );
    if (fromSettings.isNotEmpty) return fromSettings;

    final allTeams = await _service.listTeams();
    final candidates = allTeams.where(
      (t) => t.id != team.id && t.needsMedicalBag,
    );

    for (final candidate in candidates) {
      final fromExpected = _filterMedicalTemplate(
        candidate.expectedHoldings,
        validMedicalIds,
      );
      if (fromExpected.isNotEmpty) return fromExpected;
    }

    for (final candidate in candidates) {
      final fromHoldings = _filterMedicalTemplate(
        candidate.holdings,
        validMedicalIds,
      );
      if (fromHoldings.isNotEmpty) return fromHoldings;
    }

    return {for (final id in validMedicalIds) id: 1};
  }

  Future<void> _syncMedicalBagProvisioning({
    required TeamModel originalTeam,
    required String newName,
    required bool newNeedsMedicalBag,
  }) async {
    final materials = await _service.listMaterials();
    final medicalMaterialIds = materials
        .where((m) => _isMedicalBagCategory(m.category))
        .map((m) => m.id)
        .toSet();

    var latestTeam = (await _service.listTeams()).firstWhere(
      (t) => t.id == originalTeam.id,
    );

    if (!latestTeam.needsMedicalBag && newNeedsMedicalBag) {
      final template = await _resolveMedicalBagTemplateForTeam(
        latestTeam,
        medicalMaterialIds,
      );

      for (final entry in template.entries) {
        if (entry.value <= 0) continue;
        await _service.assignToTeam(
          entry.key,
          latestTeam.id,
          entry.value,
          'local',
          note: 'Lægetaske aktiveret på hold',
        );
      }

      latestTeam = (await _service.listTeams()).firstWhere(
        (t) => t.id == originalTeam.id,
      );

      final expected = Map<String, int>.from(latestTeam.expectedHoldings);
      for (final entry in template.entries) {
        if (entry.value <= 0) continue;
        expected[entry.key] = (expected[entry.key] ?? 0) + entry.value;
      }

      await _service.updateTeam(
        latestTeam.copyWith(
          expectedHoldings: expected,
          updatedAt: DateTime.now(),
        ),
      );

      latestTeam = (await _service.listTeams()).firstWhere(
        (t) => t.id == originalTeam.id,
      );
    }

    if (latestTeam.needsMedicalBag && !newNeedsMedicalBag) {
      for (final materialId in medicalMaterialIds) {
        final held = latestTeam.holdings[materialId] ?? 0;
        if (held <= 0) continue;
        await _service.returnFromTeam(
          materialId,
          latestTeam.id,
          held,
          'local',
          note: 'Lægetaske fjernet fra hold',
        );
      }

      latestTeam = (await _service.listTeams()).firstWhere(
        (t) => t.id == originalTeam.id,
      );

      final expected = Map<String, int>.from(latestTeam.expectedHoldings)
        ..removeWhere(
          (materialId, _) => medicalMaterialIds.contains(materialId),
        );

      await _service.updateTeam(
        latestTeam.copyWith(
          expectedHoldings: expected,
          updatedAt: DateTime.now(),
        ),
      );

      latestTeam = (await _service.listTeams()).firstWhere(
        (t) => t.id == originalTeam.id,
      );
    }

    await _service.updateTeam(
      latestTeam.copyWith(
        name: newName,
        needsMedicalBag: newNeedsMedicalBag,
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> _provisionMedicalBagForNewTeam(TeamModel team) async {
    final materials = await _service.listMaterials();
    final medicalMaterialIds = materials
        .where((m) => _isMedicalBagCategory(m.category))
        .map((m) => m.id)
        .toSet();
    if (medicalMaterialIds.isEmpty) return;

    final template = await _resolveMedicalBagTemplateForTeam(
      team,
      medicalMaterialIds,
    );
    if (template.isEmpty) return;

    for (final entry in template.entries) {
      if (entry.value <= 0) continue;
      await _service.assignToTeam(
        entry.key,
        team.id,
        entry.value,
        'local',
        note: 'Lægetaske tildelt ved oprettelse af hold',
      );
    }

    final updatedTeam = (await _service.listTeams()).firstWhere(
      (t) => t.id == team.id,
    );
    final expected = Map<String, int>.from(updatedTeam.expectedHoldings);
    for (final entry in template.entries) {
      if (entry.value <= 0) continue;
      expected[entry.key] = (expected[entry.key] ?? 0) + entry.value;
    }

    await _service.updateTeam(
      updatedTeam.copyWith(
        expectedHoldings: expected,
        updatedAt: DateTime.now(),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _service = widget.service;
    _loadAll();
  }

  Future<void> _loadAll() async {
    final teams = await _service.listTeams();
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      if (!mounted) return;
      setState(() {
        _canManageTeamMaterials = false;
        _teams = sortTeamsForDisplay(teams);
      });
      return;
    }

    final currentEmail = currentUser.email?.toLowerCase();
    final hasOverrideAdmin =
        currentEmail != null && _adminOverrideEmails.contains(currentEmail);

    try {
      final userSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();
      final userData = userSnapshot.data();

      final canManage = _canManageFromUserData(
        userData,
        hasOverrideAdmin: hasOverrideAdmin,
      );
      final teamIds = List<String>.from(
        userData?['teams'] as List<dynamic>? ?? const <String>[],
      );
      final teamNames = List<String>.from(
        userData?['teamNames'] as List<dynamic>? ?? const <String>[],
      );
      final teamId = userData?['teamId'] as String?;
      final teamName = userData?['teamName'] as String?;

      final assignedTeamIds = <String>{...teamIds};

      if (assignedTeamIds.isEmpty && teamId != null && teamId.isNotEmpty) {
        assignedTeamIds.add(teamId);
      }

      if (teamNames.isNotEmpty || (teamName != null && teamName.isNotEmpty)) {
        final lookup = {
          ...teamNames.map((name) => name.toLowerCase()),
          if (teamName != null && teamName.isNotEmpty) teamName.toLowerCase(),
        };
        for (final team in teams) {
          if (lookup.contains(team.name.toLowerCase())) {
            assignedTeamIds.add(team.id);
          }
        }
      }

      if (assignedTeamIds.isEmpty) {
        for (final team in teams) {
          if (team.coachId == currentUser.uid) {
            assignedTeamIds.add(team.id);
          }
        }
      }

      final visibleTeams = canManage
          ? teams
          : teams.where((team) => assignedTeamIds.contains(team.id)).toList();

      if (!mounted) return;
      setState(() {
        _canManageTeamMaterials = canManage;
        _teams = sortTeamsForDisplay(visibleTeams);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _canManageTeamMaterials = hasOverrideAdmin;
        _teams = hasOverrideAdmin ? sortTeamsForDisplay(teams) : <TeamModel>[];
      });
    }
  }

  Future<void> _persistTeamOrder(List<TeamModel> orderedTeams) async {
    final updates = <Future<void>>[];
    for (var index = 0; index < orderedTeams.length; index++) {
      final team = orderedTeams[index];
      updates.add(
        _service.updateTeam(
          team.copyWith(sortOrder: index, updatedAt: DateTime.now()),
        ),
      );
    }
    if (updates.isEmpty) return;
    await Future.wait(updates);
    await _loadAll();
  }

  Future<void> _addTeam() async {
    final nameCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) {
        var loading = false;
        var needsMedicalBag = false;
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final messenger = ScaffoldMessenger.of(context);
            final dialogNavigator = Navigator.of(context);
            return AlertDialog(
              title: const Text('Tilføj hold'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Holdnavn'),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: needsMedicalBag,
                    title: const Text('Har behov for lægetaske'),
                    onChanged: (value) =>
                        setStateDialog(() => needsMedicalBag = value),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Annuller'),
                ),
                ElevatedButton(
                  onPressed: loading
                      ? null
                      : () async {
                          final name = nameCtrl.text.trim();
                          if (name.isEmpty) return;
                          setStateDialog(() => loading = true);
                          try {
                            final team = TeamModel(
                              id: DateTime.now().millisecondsSinceEpoch
                                  .toString(),
                              name: name,
                              sortOrder: _teams.length,
                              needsMedicalBag: needsMedicalBag,
                            );
                            await _service
                                .createTeam(team)
                                .timeout(const Duration(seconds: 8));

                            if (needsMedicalBag) {
                              await _provisionMedicalBagForNewTeam(team);
                            }

                            await _loadAll();
                            if (!mounted) return;
                            dialogNavigator.pop();
                          } on TimeoutException catch (_) {
                            if (mounted) {
                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Tidsudløb ved oprettelse (Firestore svarer ikke)',
                                  ),
                                ),
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Kunne ikke oprette hold: ${e.toString()}',
                                  ),
                                ),
                              );
                            }
                          } finally {
                            if (mounted) setStateDialog(() => loading = false);
                          }
                        },
                  child: loading
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Gem'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _editTeam(TeamModel team) async {
    final nameCtrl = TextEditingController(text: team.name);
    await showDialog(
      context: context,
      builder: (context) {
        var needsMedicalBag = team.needsMedicalBag;
        final dialogNavigator = Navigator.of(context);
        final messenger = ScaffoldMessenger.of(context);
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Rediger hold'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Holdnavn'),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: needsMedicalBag,
                    title: const Text('Har behov for lægetaske'),
                    onChanged: (value) =>
                        setStateDialog(() => needsMedicalBag = value),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Annuller'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) return;
                    try {
                      await _syncMedicalBagProvisioning(
                        originalTeam: team,
                        newName: name,
                        newNeedsMedicalBag: needsMedicalBag,
                      );
                      await _loadAll();
                      if (!mounted) return;
                      dialogNavigator.pop();
                    } catch (e) {
                      if (!mounted) return;
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            'Kunne ikke gemme hold: ${e.toString()}',
                          ),
                        ),
                      );
                    }
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

  Future<void> _deleteTeam(TeamModel team) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final dialogNavigator = Navigator.of(context);
        return AlertDialog(
          title: const Text('Slet hold'),
          content: Text('Vil du slette "${team.name}"?'),
          actions: [
            TextButton(
              onPressed: () => dialogNavigator.pop(false),
              child: const Text('Annuller'),
            ),
            ElevatedButton(
              onPressed: () => dialogNavigator.pop(true),
              child: const Text('Slet'),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      await _service.deleteTeam(team.id);
      await _loadAll();
    }
  }

  void _openTeamDetail(TeamModel team) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TeamDetailPage(
          service: _service,
          team: team,
          canManageTeamMaterials: _canManageTeamMaterials,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredTeams = sortTeamsForDisplay(
      _teams.where((t) => t.name.toLowerCase().contains(_teamSearch)),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hold'),
        actions: _canManageTeamMaterials
            ? [
                IconButton(
                  tooltip: _isEditingOrder
                      ? 'Afslut redigering'
                      : 'Rediger rækkefølge',
                  onPressed: () {
                    setState(() {
                      _isEditingOrder = !_isEditingOrder;
                    });
                  },
                  icon: Icon(_isEditingOrder ? Icons.done : Icons.reorder),
                ),
              ]
            : null,
      ),
      floatingActionButton: _canManageTeamMaterials
          ? (_isEditingOrder
                ? null
                : FloatingActionButton(
                    onPressed: _addTeam,
                    child: const Icon(Icons.add),
                  ))
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Søg hold',
              ),
              onChanged: (v) =>
                  setState(() => _teamSearch = v.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: _teams.isEmpty
                ? const Center(
                    child: Text('Intet hold endnu. Tryk + for at tilføje.'),
                  )
                : (_canManageTeamMaterials
                      ? (_isEditingOrder
                            ? ReorderableListView.builder(
                                padding: EdgeInsets.only(
                                  bottom:
                                      MediaQuery.of(context).padding.bottom +
                                      88,
                                ),
                                itemCount: filteredTeams.length,
                                onReorder: (oldIndex, newIndex) async {
                                  if (oldIndex < newIndex) {
                                    newIndex -= 1;
                                  }
                                  final updatedOrder = List<TeamModel>.from(
                                    _teams,
                                  );
                                  final movedTeam = filteredTeams[oldIndex];
                                  final sourceIndex = updatedOrder.indexOf(
                                    movedTeam,
                                  );
                                  if (sourceIndex < 0) return;
                                  final reorderedTeam = updatedOrder.removeAt(
                                    sourceIndex,
                                  );
                                  final targetIndex =
                                      newIndex < updatedOrder.length
                                      ? newIndex
                                      : updatedOrder.length;
                                  updatedOrder.insert(
                                    targetIndex,
                                    reorderedTeam,
                                  );

                                  final reorderedWithPositions = <TeamModel>[];
                                  for (
                                    var index = 0;
                                    index < updatedOrder.length;
                                    index++
                                  ) {
                                    reorderedWithPositions.add(
                                      updatedOrder[index].copyWith(
                                        sortOrder: index,
                                      ),
                                    );
                                  }

                                  setState(() {
                                    _teams = reorderedWithPositions;
                                  });
                                  await _persistTeamOrder(_teams);
                                },
                                itemBuilder: (context, index) {
                                  final team = filteredTeams[index];
                                  return Card(
                                    key: ValueKey(team.id),
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    child: ListTile(
                                      leading: ReorderableDragStartListener(
                                        index: index,
                                        child: const Icon(Icons.drag_handle),
                                      ),
                                      title: Text(team.name),
                                      subtitle: Text(
                                        '${team.holdings.length} forskellige materialer · '
                                        '${team.needsMedicalBag ? 'Lægetaske: ja' : 'Lægetaske: nej'}',
                                      ),
                                      onTap: null,
                                    ),
                                  );
                                },
                              )
                            : ListView.builder(
                                padding: EdgeInsets.only(
                                  bottom:
                                      MediaQuery.of(context).padding.bottom +
                                      88,
                                ),
                                itemCount: filteredTeams.length,
                                itemBuilder: (context, index) {
                                  final team = filteredTeams[index];
                                  return Card(
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    child: ListTile(
                                      title: Text(team.name),
                                      subtitle: Text(
                                        '${team.holdings.length} forskellige materialer · '
                                        '${team.needsMedicalBag ? 'Lægetaske: ja' : 'Lægetaske: nej'}',
                                      ),
                                      onTap: () => _openTeamDetail(team),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.edit),
                                            onPressed: () => _editTeam(team),
                                          ),
                                          IconButton(
                                            icon: const Icon(
                                              Icons.delete,
                                              color: Colors.red,
                                            ),
                                            onPressed: () => _deleteTeam(team),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ))
                      : ListView.builder(
                          padding: EdgeInsets.only(
                            bottom: MediaQuery.of(context).padding.bottom + 88,
                          ),
                          itemCount: filteredTeams.length,
                          itemBuilder: (context, index) {
                            final team = filteredTeams[index];
                            return Card(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              child: ListTile(
                                title: Text(team.name),
                                subtitle: Text(
                                  '${team.holdings.length} forskellige materialer · '
                                  '${team.needsMedicalBag ? 'Lægetaske: ja' : 'Lægetaske: nej'}',
                                ),
                                onTap: () => _openTeamDetail(team),
                              ),
                            );
                          },
                        )),
          ),
        ],
      ),
    );
  }
}

class TeamDetailPage extends StatefulWidget {
  final InventoryService service;
  final TeamModel team;
  final bool canManageTeamMaterials;

  const TeamDetailPage({
    super.key,
    required this.service,
    required this.team,
    required this.canManageTeamMaterials,
  });

  @override
  State<TeamDetailPage> createState() => _TeamDetailPageState();
}

class _TeamDetailPageState extends State<TeamDetailPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late final ShortageCaseService _shortageCaseService = ShortageCaseService(
    firestore: _firestore,
  );
  static const List<String> _kitStatusOptions = [
    'ok',
    'mangler',
    'skal udskiftes',
  ];
  static const List<String> _kitColorOptions = [
    '',
    'hvid',
    'rød',
    'orange',
    'blå',
    'sort',
    'grøn',
    'gul',
    'grå',
    'navy',
  ];
  late TeamModel _team;
  List<MaterialModel> _materials = [];
  final Map<String, bool> _categoryExpanded = {};

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

  DateTime? _reportDateValue(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  Future<void> _showTeamLossReport() async {
    if (!widget.canManageTeamMaterials) return;

    final now = DateTime.now();
    final pickedRange = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      initialDateRange: DateTimeRange(
        start: now.subtract(const Duration(days: 30)),
        end: now,
      ),
      helpText: 'Vælg rapportperiode',
    );
    if (pickedRange == null) return;

    final start = DateTime(
      pickedRange.start.year,
      pickedRange.start.month,
      pickedRange.start.day,
    );
    final end = DateTime(
      pickedRange.end.year,
      pickedRange.end.month,
      pickedRange.end.day,
      23,
      59,
      59,
      999,
    );

    try {
      final snapshot = await _firestore
          .collection('bag_shortages')
          .where('teamId', isEqualTo: _team.id)
          .get();

      final byMaterial = <String, Map<String, dynamic>>{};
      var totalLost = 0;
      var totalReplaced = 0;
      var totalSelfRefilled = 0;
      var totalDelivered = 0;

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final materialId = data['materialId'] as String? ?? '';
        if (materialId.isEmpty) continue;

        final materialName = data['materialName'] as String? ?? 'Ukendt vare';
        final quantity =
            (data['reportedQuantity'] as num?)?.toInt() ??
            (data['quantity'] as num?)?.toInt() ??
            0;
        final createdAt = _reportDateValue(data['createdAt']);
        final resolvedAt = _reportDateValue(data['resolvedAt']);
        final resolutionType = data['resolutionType'] as String? ?? '';

        final materialStats = byMaterial.putIfAbsent(materialId, () {
          return {
            'materialName': materialName,
            'lost': 0,
            'replaced': 0,
            'selfRefilled': 0,
            'delivered': 0,
          };
        });

        final createdInRange =
            createdAt != null &&
            !createdAt.isBefore(start) &&
            !createdAt.isAfter(end);
        if (createdInRange && quantity > 0) {
          materialStats['lost'] = (materialStats['lost'] as int) + quantity;
          totalLost += quantity;
        }

        final resolvedInRange =
            resolvedAt != null &&
            !resolvedAt.isBefore(start) &&
            !resolvedAt.isAfter(end);
        if (!resolvedInRange || quantity <= 0) continue;

        if (resolutionType == 'self_refilled' ||
            resolutionType == 'delivered') {
          materialStats['replaced'] =
              (materialStats['replaced'] as int) + quantity;
          totalReplaced += quantity;
        }
        if (resolutionType == 'self_refilled') {
          materialStats['selfRefilled'] =
              (materialStats['selfRefilled'] as int) + quantity;
          totalSelfRefilled += quantity;
        }
        if (resolutionType == 'delivered') {
          materialStats['delivered'] =
              (materialStats['delivered'] as int) + quantity;
          totalDelivered += quantity;
        }
      }

      final rows =
          byMaterial.entries.where((entry) {
            final stats = entry.value;
            return (stats['lost'] as int) > 0 || (stats['replaced'] as int) > 0;
          }).toList()..sort((a, b) {
            final aName = (a.value['materialName'] as String).toLowerCase();
            final bName = (b.value['materialName'] as String).toLowerCase();
            return aName.compareTo(bName);
          });

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) {
          final dialogNavigator = Navigator.of(context);
          return AlertDialog(
            title: Text('Rapport: ${_team.name}'),
            content: SizedBox(
              width: 560,
              child: rows.isEmpty
                  ? const Text(
                      'Ingen registrerede mangler eller erstatninger i perioden.',
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Periode: ${pickedRange.start.day}/${pickedRange.start.month}/${pickedRange.start.year} - ${pickedRange.end.day}/${pickedRange.end.month}/${pickedRange.end.year}',
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            Chip(label: Text('Manglet/tabt: $totalLost')),
                            Chip(
                              label: Text('Erstattet i alt: $totalReplaced'),
                            ),
                            Chip(
                              label: Text('Fyldt på selv: $totalSelfRefilled'),
                            ),
                            Chip(label: Text('Udleveret: $totalDelivered')),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Opdeling pr. item',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        Flexible(
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: rows.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final stats = rows[index].value;
                              return Card(
                                margin: EdgeInsets.zero,
                                child: Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        stats['materialName'] as String,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          Chip(
                                            label: Text(
                                              'Manglet/tabt: ${stats['lost']}',
                                            ),
                                          ),
                                          Chip(
                                            label: Text(
                                              'Erstattet: ${stats['replaced']}',
                                            ),
                                          ),
                                          Chip(
                                            label: Text(
                                              'Fyldt på selv: ${stats['selfRefilled']}',
                                            ),
                                          ),
                                          Chip(
                                            label: Text(
                                              'Udleveret: ${stats['delivered']}',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => dialogNavigator.pop(),
                child: const Text('Luk'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Kunne ikke hente rapport: $e')));
    }
  }

  bool _materialExists(String materialId) {
    return _materials.any((m) => m.id == materialId);
  }

  Future<void> _setActualHolding(String materialId) async {
    if (!widget.canManageTeamMaterials) return;
    if (!_materialExists(materialId)) {
      await _removeUnknownMaterialEntry(materialId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ukendt vare blev fjernet fra holdet.')),
      );
      return;
    }

    final current = teamActualMaterialCount(_team, materialId);
    final currentExpected = teamExpectedMaterialCount(_team, materialId);
    final qtyCtrl = TextEditingController(text: current.toString());
    final expectedCtrl = TextEditingController(
      text: currentExpected?.toString() ?? '',
    );

    await showDialog<void>(
      context: context,
      builder: (context) {
        final dialogNavigator = Navigator.of(context);
        final messenger = ScaffoldMessenger.of(context);
        return AlertDialog(
          title: const Text('Juster beholdning på holdet'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: qtyCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Nyt antal på holdet',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: expectedCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Forventet beholdning',
                  helperText: 'Tom = ikke sat',
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
                final target = int.tryParse(qtyCtrl.text.trim());
                if (target == null || target < 0) return;
                final expectedText = expectedCtrl.text.trim();
                final expectedTarget = expectedText.isEmpty
                    ? null
                    : int.tryParse(expectedText);
                if (expectedTarget != null && expectedTarget < 0) return;
                if (expectedText.isNotEmpty && expectedTarget == null) return;

                final expectedChanged = expectedTarget != currentExpected;
                if (target == current && !expectedChanged) {
                  dialogNavigator.pop();
                  return;
                }

                try {
                  if (target > current) {
                    await widget.service.assignToTeam(
                      materialId,
                      _team.id,
                      target - current,
                      'local',
                      note: 'Juster beholdning på hold',
                    );
                  } else {
                    await widget.service.returnFromTeam(
                      materialId,
                      _team.id,
                      current - target,
                      'local',
                      note: 'Juster beholdning på hold',
                    );
                  }

                  var updatedTeam = (await widget.service.listTeams())
                      .firstWhere((t) => t.id == _team.id);

                  if (expectedChanged) {
                    final newExpected = Map<String, int>.from(
                      updatedTeam.expectedHoldings,
                    );
                    if (expectedTarget == null) {
                      newExpected.remove(materialId);
                    } else {
                      newExpected[materialId] = expectedTarget;
                    }

                    await widget.service.updateTeam(
                      updatedTeam.copyWith(
                        expectedHoldings: newExpected,
                        updatedAt: DateTime.now(),
                      ),
                    );
                    updatedTeam = (await widget.service.listTeams()).firstWhere(
                      (t) => t.id == _team.id,
                    );
                  }

                  if (!mounted) return;
                  setState(() => _team = updatedTeam);
                  await _loadMaterials();
                  dialogNavigator.pop();
                } catch (e) {
                  if (!mounted) return;
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('Kunne ikke justere beholdning: $e'),
                    ),
                  );
                }
              },
              child: const Text('Gem'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _removeMaterialCompletely(String materialId) async {
    if (!widget.canManageTeamMaterials) return;

    final label = _materialLabel(_materialForId(materialId));
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final dialogNavigator = Navigator.of(context);
        return AlertDialog(
          title: const Text('Fjern materiale fra hold'),
          content: Text('Vil du fjerne "$label" helt fra holdet?'),
          actions: [
            TextButton(
              onPressed: () => dialogNavigator.pop(false),
              child: const Text('Annuller'),
            ),
            ElevatedButton(
              onPressed: () => dialogNavigator.pop(true),
              child: const Text('Fjern'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    if (!_materialExists(materialId)) {
      await _removeUnknownMaterialEntry(materialId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ukendt vare blev fjernet fra holdet.')),
      );
      return;
    }

    final currentHeld = teamActualMaterialCount(_team, materialId);
    if (currentHeld <= 0) {
      await _removeUnknownMaterialEntry(materialId);
      return;
    }

    try {
      await widget.service.returnFromTeam(
        materialId,
        _team.id,
        currentHeld,
        'local',
        note: 'Fjern materiale helt fra hold',
      );
      final updatedTeam = (await widget.service.listTeams()).firstWhere(
        (t) => t.id == _team.id,
      );
      if (!mounted) return;
      setState(() => _team = updatedTeam);
      await _loadMaterials();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunne ikke fjerne materiale: $e')),
      );
    }
  }

  Future<void> _removeUnknownMaterialEntry(String materialId) async {
    if (!widget.canManageTeamMaterials) return;
    final holdings = Map<String, int>.from(_team.holdings)..remove(materialId);
    final expected = Map<String, int>.from(_team.expectedHoldings)
      ..remove(materialId);

    await widget.service.updateTeam(
      _team.copyWith(
        holdings: holdings,
        expectedHoldings: expected,
        updatedAt: DateTime.now(),
      ),
    );

    final updatedTeam = (await widget.service.listTeams()).firstWhere(
      (t) => t.id == _team.id,
    );
    if (!mounted) return;
    setState(() => _team = updatedTeam);
  }

  List<Widget> _buildStructuredHoldings(List<MapEntry<String, int>> entries) {
    final grouped = <String, List<MapEntry<String, int>>>{};

    for (final entry in entries) {
      final material = _materialForId(entry.key);
      final category = material.category.trim().isEmpty
          ? 'Ukendt'
          : material.category;
      grouped.putIfAbsent(category, () => []).add(entry);
    }

    final categories = grouped.keys.toList()..sort();
    final widgets = <Widget>[];

    for (final category in categories) {
      final items = grouped[category]!;
      final isExpanded = _categoryExpanded.putIfAbsent(category, () => false);
      items.sort((a, b) {
        final aName = _materialLabel(_materialForId(a.key));
        final bName = _materialLabel(_materialForId(b.key));
        return aName.toLowerCase().compareTo(bName.toLowerCase());
      });

      widgets.add(
        Card(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: ExpansionTile(
            key: PageStorageKey<String>('hold-category-$category'),
            initiallyExpanded: isExpanded,
            onExpansionChanged: (expanded) {
              setState(() {
                _categoryExpanded[category] = expanded;
              });
            },
            title: Text(
              '$category (${items.length})',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            children: items.map((entry) {
              final material = _materialForId(entry.key);
              final label = _materialLabel(material);
              final isUnknownMaterial = !_materialExists(entry.key);
              final actual = teamActualMaterialCount(_team, entry.key);
              final expected = teamExpectedMaterialCount(_team, entry.key);
              final missing = expected == null
                  ? null
                  : teamMissingMaterialCount(_team, entry.key);

              return Card(
                margin: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              label,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => _reportMaterialStatus(entry.key),
                            icon: const Icon(Icons.assignment_turned_in),
                            label: const Text('Indberet beholdning'),
                          ),
                          if (widget.canManageTeamMaterials)
                            PopupMenuButton<String>(
                              tooltip: 'Administrer materiale',
                              onSelected: (value) async {
                                switch (value) {
                                  case 'replace':
                                    if (!isUnknownMaterial) {
                                      await _replaceAssignedMaterial(entry.key);
                                    }
                                    break;
                                  case 'actual':
                                    await _setActualHolding(entry.key);
                                    break;
                                  case 'remove':
                                    await _removeMaterialCompletely(entry.key);
                                    break;
                                }
                              },
                              itemBuilder: (context) {
                                final items = <PopupMenuEntry<String>>[];
                                if (!isUnknownMaterial) {
                                  items.add(
                                    const PopupMenuItem<String>(
                                      value: 'replace',
                                      child: Text('Skift materiale'),
                                    ),
                                  );
                                }
                                items.addAll([
                                  const PopupMenuItem<String>(
                                    value: 'actual',
                                    child: Text('Juster beholdning'),
                                  ),
                                  PopupMenuItem<String>(
                                    value: 'remove',
                                    child: Text(
                                      isUnknownMaterial
                                          ? 'Ryd ukendt vare'
                                          : 'Fjern fra hold',
                                    ),
                                  ),
                                ]);
                                return items;
                              },
                              child: const Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 6,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.settings),
                                    SizedBox(width: 4),
                                    Text('Administrer'),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          Chip(label: Text('Status: $actual')),
                          Chip(
                            label: Text(
                              expected == null
                                  ? 'Forventet: ikke sat'
                                  : 'Forventet: $expected',
                            ),
                          ),
                          if (missing != null)
                            Chip(
                              label: Text('Mangler: $missing'),
                              backgroundColor: missing > 0
                                  ? Colors.red.shade50
                                  : Colors.green.shade50,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      );
    }

    return widgets;
  }

  String _kitStatusLabel(String value) {
    switch (value) {
      case 'ok':
        return 'Ok';
      case 'mangler':
        return 'Mangler';
      case 'skal udskiftes':
        return 'Skal udskiftes';
      default:
        return value;
    }
  }

  String _kitSizeLabel(String value) {
    return value.trim().isEmpty ? 'ikke sat' : value.trim();
  }

  String _kitColorLabel(String value) {
    return value.trim().isEmpty ? 'ikke sat' : value.trim();
  }

  Color _kitStatusColor(String value) {
    switch (value) {
      case 'ok':
        return Colors.green;
      case 'mangler':
        return Colors.red;
      case 'skal udskiftes':
        return Colors.orange;
      default:
        return Colors.blueGrey;
    }
  }

  String _kitSetOverallStatus(TeamKitSetModel kitSet) {
    final statuses = [
      kitSet.jerseyStatus,
      kitSet.shortsStatus,
      kitSet.socksStatus,
      kitSet.duffelbagStatus,
    ];
    if (statuses.any((status) => status == 'mangler')) {
      return 'Mangler';
    }
    if (statuses.any((status) => status == 'skal udskiftes')) {
      return 'Skal udskiftes';
    }
    return 'Komplet';
  }

  Map<String, int> _kitSetStats() {
    final stats = <String, int>{
      'Komplet': 0,
      'Mangler': 0,
      'Skal udskiftes': 0,
    };
    for (final kitSet in _team.kitSets) {
      stats[_kitSetOverallStatus(kitSet)] =
          (stats[_kitSetOverallStatus(kitSet)] ?? 0) + 1;
    }
    return stats;
  }

  Future<void> _reloadTeam() async {
    final refreshed = (await widget.service.listTeams()).firstWhere(
      (team) => team.id == _team.id,
    );
    if (!mounted) return;
    setState(() => _team = refreshed);
  }

  Future<void> _saveKitSet(TeamKitSetModel kitSet) async {
    final newKitSets = List<TeamKitSetModel>.from(_team.kitSets);
    final existingIndex = newKitSets.indexWhere((item) => item.id == kitSet.id);
    if (existingIndex >= 0) {
      newKitSets[existingIndex] = kitSet;
    } else {
      newKitSets.add(kitSet);
    }

    await widget.service.updateTeam(
      _team.copyWith(kitSets: newKitSets, updatedAt: DateTime.now()),
    );
    await _reloadTeam();
  }

  Future<void> _saveKitSets(List<TeamKitSetModel> kitSets) async {
    await widget.service.updateTeam(
      _team.copyWith(kitSets: kitSets, updatedAt: DateTime.now()),
    );
    await _reloadTeam();
  }

  Future<void> _showBulkPartDialog({
    required String partKey,
    required String partLabel,
  }) async {
    final setNumbersCtrl = TextEditingController();
    final sizeCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    String color = partKey == 'jersey'
        ? 'hvid'
        : partKey == 'shorts' || partKey == 'socks'
        ? 'rød'
        : '';
    String status = 'ok';

    await showDialog<void>(
      context: context,
      builder: (context) {
        final dialogNavigator = Navigator.of(context);
        final messenger = ScaffoldMessenger.of(context);
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text('Batch registrering: $partLabel'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: setNumbersCtrl,
                      minLines: 3,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        labelText: 'Sæt-numre',
                        hintText: 'Fx: 1,2,3 eller én pr linje',
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: color,
                      decoration: InputDecoration(
                        labelText: '$partLabel farve',
                      ),
                      items: _kitColorOptions
                          .map(
                            (value) => DropdownMenuItem<String>(
                              value: value,
                              child: Text(_kitColorLabel(value)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setStateDialog(() => color = value);
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: sizeCtrl,
                      decoration: InputDecoration(
                        labelText: '$partLabel størrelse',
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: status,
                      decoration: InputDecoration(
                        labelText: '$partLabel status',
                      ),
                      items: _kitStatusOptions
                          .map(
                            (value) => DropdownMenuItem<String>(
                              value: value,
                              child: Text(_kitStatusLabel(value)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setStateDialog(() => status = value);
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: noteCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Note (valgfri)',
                      ),
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
                    final raw = setNumbersCtrl.text;
                    final setNumbers = raw
                        .split(RegExp(r'[\n,;]+'))
                        .map((s) => s.trim())
                        .where((s) => s.isNotEmpty)
                        .toSet()
                        .toList();

                    if (setNumbers.isEmpty) return;

                    try {
                      final now = DateTime.now();
                      final byId = <String, TeamKitSetModel>{
                        for (final set in _team.kitSets) set.id: set,
                      };

                      for (var i = 0; i < setNumbers.length; i++) {
                        final setNumber = setNumbers[i];
                        final existing = _team.kitSets.where((set) {
                          return set.setNumber.trim().toLowerCase() ==
                              setNumber.toLowerCase();
                        }).firstOrNull;

                        final base =
                            existing ??
                            TeamKitSetModel(
                              id: '${now.millisecondsSinceEpoch}-$i',
                              setNumber: setNumber,
                              createdAt: now,
                              updatedAt: now,
                            );

                        TeamKitSetModel updated;
                        switch (partKey) {
                          case 'jersey':
                            updated = base.copyWith(
                              jerseyColor: color,
                              jerseySize: sizeCtrl.text.trim(),
                              jerseyStatus: status,
                              note: noteCtrl.text.trim().isEmpty
                                  ? base.note
                                  : noteCtrl.text.trim(),
                              updatedAt: now,
                            );
                            break;
                          case 'shorts':
                            updated = base.copyWith(
                              shortsColor: color,
                              shortsSize: sizeCtrl.text.trim(),
                              shortsStatus: status,
                              note: noteCtrl.text.trim().isEmpty
                                  ? base.note
                                  : noteCtrl.text.trim(),
                              updatedAt: now,
                            );
                            break;
                          case 'socks':
                            updated = base.copyWith(
                              socksColor: color,
                              socksSize: sizeCtrl.text.trim(),
                              socksStatus: status,
                              note: noteCtrl.text.trim().isEmpty
                                  ? base.note
                                  : noteCtrl.text.trim(),
                              updatedAt: now,
                            );
                            break;
                          default:
                            updated = base;
                        }

                        byId[updated.id] = updated;
                      }

                      await _saveKitSets(byId.values.toList());
                      if (!mounted) return;
                      dialogNavigator.pop();
                    } catch (e) {
                      if (!mounted) return;
                      messenger.showSnackBar(
                        SnackBar(content: Text('Kunne ikke gemme batch: $e')),
                      );
                    }
                  },
                  child: const Text('Gem batch'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _deleteKitSet(TeamKitSetModel kitSet) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final dialogNavigator = Navigator.of(context);
        return AlertDialog(
          title: const Text('Slet sæt'),
          content: Text('Vil du slette sæt ${kitSet.setNumber}?'),
          actions: [
            TextButton(
              onPressed: () => dialogNavigator.pop(false),
              child: const Text('Annuller'),
            ),
            ElevatedButton(
              onPressed: () => dialogNavigator.pop(true),
              child: const Text('Slet'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;
    final newKitSets = _team.kitSets
        .where((item) => item.id != kitSet.id)
        .toList();
    await widget.service.updateTeam(
      _team.copyWith(kitSets: newKitSets, updatedAt: DateTime.now()),
    );
    await _reloadTeam();
  }

  Future<void> _showKitSetDialog({TeamKitSetModel? existing}) async {
    final numberCtrl = TextEditingController(text: existing?.setNumber ?? '');
    String jerseyColor = existing?.jerseyColor ?? '';
    final jerseySizeCtrl = TextEditingController(
      text: existing?.jerseySize ?? '',
    );
    final shortsSizeCtrl = TextEditingController(
      text: existing?.shortsSize ?? '',
    );
    String shortsColor = existing?.shortsColor ?? '';
    final socksSizeCtrl = TextEditingController(
      text: existing?.socksSize ?? '',
    );
    String socksColor = existing?.socksColor ?? '';
    final noteCtrl = TextEditingController(text: existing?.note ?? '');
    String duffelbagColor = existing?.duffelbagColor ?? '';
    String jerseyStatus = existing?.jerseyStatus ?? 'ok';
    String shortsStatus = existing?.shortsStatus ?? 'ok';
    String socksStatus = existing?.socksStatus ?? 'ok';
    String duffelbagStatus = existing?.duffelbagStatus ?? 'ok';

    await showDialog<void>(
      context: context,
      builder: (context) {
        final dialogNavigator = Navigator.of(context);
        final messenger = ScaffoldMessenger.of(context);

        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text(existing == null ? 'Opret sæt' : 'Redigér sæt'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: numberCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nummer på sættet / rygnummer',
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: jerseyColor,
                      decoration: const InputDecoration(
                        labelText: 'Trøje farve',
                      ),
                      items: _kitColorOptions
                          .map(
                            (value) => DropdownMenuItem<String>(
                              value: value,
                              child: Text(_kitColorLabel(value)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setStateDialog(() => jerseyColor = value);
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: jerseySizeCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Trøje størrelse',
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: jerseyStatus,
                      decoration: const InputDecoration(
                        labelText: 'Trøje status',
                      ),
                      items: _kitStatusOptions
                          .map(
                            (value) => DropdownMenuItem<String>(
                              value: value,
                              child: Text(_kitStatusLabel(value)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setStateDialog(() => jerseyStatus = value);
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: shortsSizeCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Shorts størrelse',
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: shortsColor,
                      decoration: const InputDecoration(
                        labelText: 'Shorts farve',
                      ),
                      items: _kitColorOptions
                          .map(
                            (value) => DropdownMenuItem<String>(
                              value: value,
                              child: Text(_kitColorLabel(value)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setStateDialog(() => shortsColor = value);
                      },
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: shortsStatus,
                      decoration: const InputDecoration(
                        labelText: 'Shorts status',
                      ),
                      items: _kitStatusOptions
                          .map(
                            (value) => DropdownMenuItem<String>(
                              value: value,
                              child: Text(_kitStatusLabel(value)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setStateDialog(() => shortsStatus = value);
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: socksSizeCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Strømper størrelse',
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: socksColor,
                      decoration: const InputDecoration(
                        labelText: 'Strømper farve',
                      ),
                      items: _kitColorOptions
                          .map(
                            (value) => DropdownMenuItem<String>(
                              value: value,
                              child: Text(_kitColorLabel(value)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setStateDialog(() => socksColor = value);
                      },
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: socksStatus,
                      decoration: const InputDecoration(
                        labelText: 'Strømper status',
                      ),
                      items: _kitStatusOptions
                          .map(
                            (value) => DropdownMenuItem<String>(
                              value: value,
                              child: Text(_kitStatusLabel(value)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setStateDialog(() => socksStatus = value);
                      },
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: duffelbagStatus,
                      decoration: const InputDecoration(
                        labelText: 'Duffelbag status',
                      ),
                      items: _kitStatusOptions
                          .map(
                            (value) => DropdownMenuItem<String>(
                              value: value,
                              child: Text(_kitStatusLabel(value)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setStateDialog(() => duffelbagStatus = value);
                      },
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: duffelbagColor,
                      decoration: const InputDecoration(
                        labelText: 'Duffelbag farve',
                      ),
                      items: _kitColorOptions
                          .map(
                            (value) => DropdownMenuItem<String>(
                              value: value,
                              child: Text(_kitColorLabel(value)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setStateDialog(() => duffelbagColor = value);
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: noteCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Note (valgfri)',
                      ),
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
                    final number = numberCtrl.text.trim();
                    if (number.isEmpty) return;

                    final now = DateTime.now();
                    final kitSet = TeamKitSetModel(
                      id: existing?.id ?? now.millisecondsSinceEpoch.toString(),
                      setNumber: number,
                      jerseyColor: jerseyColor,
                      jerseySize: jerseySizeCtrl.text.trim(),
                      jerseyStatus: jerseyStatus,
                      shortsColor: shortsColor,
                      shortsSize: shortsSizeCtrl.text.trim(),
                      shortsStatus: shortsStatus,
                      socksColor: socksColor,
                      socksSize: socksSizeCtrl.text.trim(),
                      socksStatus: socksStatus,
                      duffelbagColor: duffelbagColor,
                      duffelbagStatus: duffelbagStatus,
                      note: noteCtrl.text.trim().isEmpty
                          ? null
                          : noteCtrl.text.trim(),
                      createdAt: existing?.createdAt ?? now,
                      updatedAt: now,
                    );

                    try {
                      await _saveKitSet(kitSet);
                      if (!mounted) return;
                      dialogNavigator.pop();
                    } catch (e) {
                      if (!mounted) return;
                      messenger.showSnackBar(
                        SnackBar(content: Text('Kunne ikke gemme sæt: $e')),
                      );
                    }
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

  Widget _buildKitSetsSection() {
    final stats = _kitSetStats();

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Udlåns spillertøj',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Hvert sæt indeholder trøje, shorts, strømper og duffelbag som separate dele.',
            ),
            if (widget.canManageTeamMaterials) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _showBulkPartDialog(
                      partKey: 'jersey',
                      partLabel: 'Trøje',
                    ),
                    icon: const Icon(Icons.checkroom),
                    label: const Text('Registrer trøjer'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _showBulkPartDialog(
                      partKey: 'shorts',
                      partLabel: 'Shorts',
                    ),
                    icon: const Icon(Icons.style),
                    label: const Text('Registrer shorts'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _showBulkPartDialog(
                      partKey: 'socks',
                      partLabel: 'Strømper',
                    ),
                    icon: const Icon(Icons.dry_cleaning),
                    label: const Text('Registrer strømper'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                Chip(
                  avatar: const Icon(Icons.check_circle, size: 18),
                  label: Text('Komplet: ${stats['Komplet'] ?? 0}'),
                  backgroundColor: Colors.green.shade50,
                ),
                Chip(
                  avatar: const Icon(Icons.report_problem, size: 18),
                  label: Text('Mangler: ${stats['Mangler'] ?? 0}'),
                  backgroundColor: Colors.red.shade50,
                ),
                Chip(
                  avatar: const Icon(Icons.refresh, size: 18),
                  label: Text(
                    'Skal udskiftes: ${stats['Skal udskiftes'] ?? 0}',
                  ),
                  backgroundColor: Colors.orange.shade50,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_team.kitSets.isEmpty)
              const Text('Ingen sæt registreret endnu.')
            else
              Column(
                children: _team.kitSets.map((kitSet) {
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ExpansionTile(
                      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      title: Text(
                        'Sæt ${kitSet.setNumber}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        _kitSetOverallStatus(kitSet),
                        style: TextStyle(
                          color: _kitStatusColor(_kitSetOverallStatus(kitSet)),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      trailing: widget.canManageTeamMaterials
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit),
                                  tooltip: 'Redigér sæt',
                                  onPressed: () =>
                                      _showKitSetDialog(existing: kitSet),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete,
                                    color: Colors.red,
                                  ),
                                  tooltip: 'Slet sæt',
                                  onPressed: () => _deleteKitSet(kitSet),
                                ),
                              ],
                            )
                          : null,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            Chip(
                              label: Text(
                                'Trøje: ${_kitColorLabel(kitSet.jerseyColor)} · ${_kitSizeLabel(kitSet.jerseySize)} · ${_kitStatusLabel(kitSet.jerseyStatus)}',
                              ),
                            ),
                            Chip(
                              label: Text(
                                'Shorts: ${_kitColorLabel(kitSet.shortsColor)} · ${_kitSizeLabel(kitSet.shortsSize)} · ${_kitStatusLabel(kitSet.shortsStatus)}',
                              ),
                            ),
                            Chip(
                              label: Text(
                                'Strømper: ${_kitColorLabel(kitSet.socksColor)} · ${_kitSizeLabel(kitSet.socksSize)} · ${_kitStatusLabel(kitSet.socksStatus)}',
                              ),
                            ),
                            Chip(
                              label: Text(
                                'Duffelbag: ${_kitColorLabel(kitSet.duffelbagColor)} · ${_kitStatusLabel(kitSet.duffelbagStatus)}',
                              ),
                            ),
                          ],
                        ),
                        if ((kitSet.note ?? '').trim().isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text('Note: ${kitSet.note!.trim()}'),
                          ),
                        ],
                      ],
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _team = widget.team;
    _loadMaterials();
  }

  Future<void> _loadMaterials() async {
    final m = await widget.service.listMaterials();
    setState(() => _materials = m);
  }

  Future<void> _assignMaterial() async {
    if (!widget.canManageTeamMaterials) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Kun admin og materialforvalter kan tildele materialer.',
          ),
        ),
      );
      return;
    }

    final qtyCtrl = TextEditingController(text: '1');
    final expectedCtrl = TextEditingController();
    MaterialModel? selected;
    String? selectedCategory;
    String materialSearch = '';

    await showDialog(
      context: context,
      builder: (context) {
        final dialogNavigator = Navigator.of(context);
        final messenger = ScaffoldMessenger.of(context);
        return AlertDialog(
          title: const Text('Tildel materiale'),
          content: StatefulBuilder(
            builder: (context, setStateDialog) {
              final categories =
                  _materials
                      .map(
                        (m) =>
                            m.category.trim().isEmpty ? 'Ukendt' : m.category,
                      )
                      .toSet()
                      .toList()
                    ..sort(
                      (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
                    );

              final filtered =
                  _materials.where((m) {
                    final categoryName = m.category.trim().isEmpty
                        ? 'Ukendt'
                        : m.category;
                    if (selectedCategory == null ||
                        categoryName != selectedCategory) {
                      return false;
                    }
                    final label = ('${m.name} ${m.variant ?? ''}')
                        .toLowerCase();
                    return materialSearch.isEmpty ||
                        label.contains(materialSearch);
                  }).toList()..sort((a, b) {
                    final aLabel = _materialLabel(a).toLowerCase();
                    final bLabel = _materialLabel(b).toLowerCase();
                    return aLabel.compareTo(bLabel);
                  });

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: selectedCategory,
                    hint: const Text('Vælg kategori'),
                    isExpanded: true,
                    items: categories
                        .map(
                          (c) => DropdownMenuItem<String>(
                            value: c,
                            child: Text(c),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setStateDialog(() {
                      selectedCategory = v;
                      selected = null;
                    }),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    enabled: selectedCategory != null,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Søg materiale',
                    ),
                    onChanged: (v) => setStateDialog(
                      () => materialSearch = v.trim().toLowerCase(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButton<MaterialModel>(
                    value: selected,
                    hint: Text(
                      selectedCategory == null
                          ? 'Vælg først en kategori'
                          : 'Vælg materiale',
                    ),
                    isExpanded: true,
                    items: filtered.map((m) {
                      final label = (m.variant == null || m.variant!.isEmpty)
                          ? m.name
                          : '${m.name} · ${m.variant}';
                      return DropdownMenuItem(
                        value: m,
                        child: Text('$label (${m.totalInStock})'),
                      );
                    }).toList(),
                    onChanged: (v) => setStateDialog(() {
                      selected = v;
                      if (v == null) {
                        expectedCtrl.clear();
                        return;
                      }
                      final existingExpected = _team.expectedHoldings[v.id];
                      expectedCtrl.text =
                          (existingExpected ??
                                  (int.tryParse(qtyCtrl.text) ?? 0))
                              .toString();
                    }),
                  ),
                  TextField(
                    controller: qtyCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Antal'),
                  ),
                  TextField(
                    controller: expectedCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Forventet beholdning',
                      helperText: 'Valgfri. Sættes sammen med tildelingen.',
                    ),
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => dialogNavigator.pop(),
              child: const Text('Annuller'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (selectedCategory == null || selected == null) return;
                final qty = int.tryParse(qtyCtrl.text) ?? 0;
                if (qty <= 0) return;
                final expectedText = expectedCtrl.text.trim();
                final expected = expectedText.isEmpty
                    ? null
                    : int.tryParse(expectedText);
                if (expected != null && expected < 0) return;
                if (expectedText.isNotEmpty && expected == null) return;

                try {
                  await widget.service.assignToTeam(
                    selected!.id,
                    _team.id,
                    qty,
                    'local',
                  );
                  var updatedTeam = (await widget.service.listTeams())
                      .firstWhere((t) => t.id == _team.id);

                  if (expected != null) {
                    final newExpected = Map<String, int>.from(
                      updatedTeam.expectedHoldings,
                    )..[selected!.id] = expected;

                    await widget.service.updateTeam(
                      updatedTeam.copyWith(
                        expectedHoldings: newExpected,
                        updatedAt: DateTime.now(),
                      ),
                    );
                    updatedTeam = (await widget.service.listTeams()).firstWhere(
                      (t) => t.id == _team.id,
                    );
                  }

                  if (!mounted) return;
                  setState(() => _team = updatedTeam);
                  await _loadMaterials();
                  dialogNavigator.pop();
                } on TimeoutException catch (_) {
                  if (mounted) {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Tidsudløb ved tildeling af materiale'),
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text('Kunne ikke tildele materiale: $e'),
                      ),
                    );
                  }
                }
              },
              child: const Text('Tildel'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _reportMaterialStatus(String materialId) async {
    final material = _materialForId(materialId);
    final materialLabel = _materialLabel(material);
    final currentStatus = teamActualMaterialCount(_team, materialId);
    final expected = teamExpectedMaterialCount(_team, materialId);
    final statusCtrl = TextEditingController(text: currentStatus.toString());
    final reasonCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) {
        final dialogNavigator = Navigator.of(context);
        final messenger = ScaffoldMessenger.of(context);

        return AlertDialog(
          title: const Text('Indmeld status på materiale'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(materialLabel),
                const SizedBox(height: 8),
                Text('Registreret status: $currentStatus ${material.unit}'),
                Text(
                  expected == null
                      ? 'Forventet beholdning: ikke sat'
                      : 'Forventet beholdning: $expected ${material.unit}',
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: statusCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Status nu (antal)',
                  ),
                ),
                TextField(
                  controller: reasonCtrl,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Begrundelse ved mangel',
                    hintText:
                        'Påkrævet når status er lavere end forventet beholdning.',
                  ),
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
                final reported = int.tryParse(statusCtrl.text.trim());
                if (reported == null || reported < 0) return;

                final missing = expected == null
                    ? 0
                    : (expected - reported) > 0
                    ? (expected - reported)
                    : 0;
                final reason = reasonCtrl.text.trim();
                if (missing > 0 && reason.isEmpty) {
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Skriv begrundelse, når der er mangel på materialet.',
                      ),
                    ),
                  );
                  return;
                }

                try {
                  final user = FirebaseAuth.instance.currentUser;
                  await _firestore.collection('bag_status_reports').add({
                    'teamId': _team.id,
                    'teamName': _team.name,
                    'materialId': materialId,
                    'materialName': materialLabel,
                    'reportedQuantity': reported,
                    'registeredQuantity': currentStatus,
                    'expectedQuantity': expected,
                    'missingQuantity': missing,
                    'note': reason,
                    'source': 'hold_status',
                    'createdAt': FieldValue.serverTimestamp(),
                    'reportedByUid': user?.uid,
                    'reportedByEmail': user?.email,
                  });

                  if (missing > 0) {
                    await _shortageCaseService.upsertOpenCase(
                      teamId: _team.id,
                      teamName: _team.name,
                      materialId: materialId,
                      materialName: materialLabel,
                      reportedQuantity: missing,
                      note: reason,
                      source: 'hold_status_report',
                      reportedByUid: user?.uid,
                      reportedByEmail: user?.email,
                    );
                  }

                  // Keep the team holdings in sync with the reported count.
                  final newHoldings = Map<String, int>.from(_team.holdings);
                  if (reported <= 0) {
                    newHoldings.remove(materialId);
                  } else {
                    newHoldings[materialId] = reported;
                  }

                  String resultMessage;
                  try {
                    await widget.service.updateTeam(
                      _team.copyWith(
                        holdings: newHoldings,
                        updatedAt: DateTime.now(),
                      ),
                    );
                    final refreshedTeam = (await widget.service.listTeams())
                        .firstWhere((t) => t.id == _team.id);
                    if (!mounted) return;
                    setState(() => _team = refreshedTeam);
                    await _loadMaterials();
                    resultMessage = missing > 0
                        ? 'Status og beholdning gemt. Mangelsag er oprettet/opdateret.'
                        : 'Status og beholdning gemt.';
                  } catch (_) {
                    resultMessage = missing > 0
                        ? 'Status gemt, men beholdning kunne ikke opdateres. Mangelsag er oprettet/opdateret.'
                        : 'Status gemt, men beholdning kunne ikke opdateres.';
                  }

                  messenger.showSnackBar(
                    SnackBar(content: Text(resultMessage)),
                  );
                  dialogNavigator.pop();
                } catch (e) {
                  if (!mounted) return;
                  messenger.showSnackBar(
                    SnackBar(content: Text('Kunne ikke gemme status: $e')),
                  );
                }
              },
              child: const Text('Gem status'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _replaceAssignedMaterial(String fromMaterialId) async {
    if (!widget.canManageTeamMaterials) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Kun admin og materialforvalter kan rette tildelinger.',
          ),
        ),
      );
      return;
    }

    final currentHeld = teamActualMaterialCount(_team, fromMaterialId);
    if (currentHeld <= 0) return;

    final qtyCtrl = TextEditingController(text: currentHeld.toString());
    final expectedCtrl = TextEditingController();
    final fromMaterial = _materialForId(fromMaterialId);
    final fromLabel = _materialLabel(fromMaterial);

    MaterialModel? selected;
    String? selectedCategory;
    String materialSearch = '';

    await showDialog(
      context: context,
      builder: (context) {
        final dialogNavigator = Navigator.of(context);
        final messenger = ScaffoldMessenger.of(context);

        return AlertDialog(
          title: const Text('Ret tildeling'),
          content: StatefulBuilder(
            builder: (context, setStateDialog) {
              final categories =
                  _materials
                      .map(
                        (m) =>
                            m.category.trim().isEmpty ? 'Ukendt' : m.category,
                      )
                      .toSet()
                      .toList()
                    ..sort(
                      (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
                    );

              final filtered =
                  _materials.where((m) {
                    if (m.id == fromMaterialId) return false;
                    final categoryName = m.category.trim().isEmpty
                        ? 'Ukendt'
                        : m.category;
                    if (selectedCategory == null ||
                        categoryName != selectedCategory) {
                      return false;
                    }
                    final label = ('${m.name} ${m.variant ?? ''}')
                        .toLowerCase();
                    return materialSearch.isEmpty ||
                        label.contains(materialSearch);
                  }).toList()..sort((a, b) {
                    final aLabel = _materialLabel(a).toLowerCase();
                    final bLabel = _materialLabel(b).toLowerCase();
                    return aLabel.compareTo(bLabel);
                  });

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Nuværende vare: $fromLabel'),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: selectedCategory,
                    hint: const Text('Vælg kategori for ny vare'),
                    isExpanded: true,
                    items: categories
                        .map(
                          (c) => DropdownMenuItem<String>(
                            value: c,
                            child: Text(c),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setStateDialog(() {
                      selectedCategory = v;
                      selected = null;
                    }),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    enabled: selectedCategory != null,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Søg ny vare',
                    ),
                    onChanged: (v) => setStateDialog(
                      () => materialSearch = v.trim().toLowerCase(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButton<MaterialModel>(
                    value: selected,
                    hint: Text(
                      selectedCategory == null
                          ? 'Vælg først en kategori'
                          : 'Vælg ny vare',
                    ),
                    isExpanded: true,
                    items: filtered.map((m) {
                      final label = (m.variant == null || m.variant!.isEmpty)
                          ? m.name
                          : '${m.name} · ${m.variant}';
                      return DropdownMenuItem(
                        value: m,
                        child: Text('$label (${m.totalInStock})'),
                      );
                    }).toList(),
                    onChanged: (v) => setStateDialog(() {
                      selected = v;
                      if (v == null) {
                        expectedCtrl.clear();
                        return;
                      }
                      final existingExpected = _team.expectedHoldings[v.id];
                      expectedCtrl.text =
                          (existingExpected ??
                                  (int.tryParse(qtyCtrl.text) ?? 0))
                              .toString();
                    }),
                  ),
                  TextField(
                    controller: qtyCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Nyt antal på holdet (ny vare)',
                      helperText:
                          'Eksisterende vare ($fromLabel) fjernes helt fra holdet.',
                    ),
                  ),
                  TextField(
                    controller: expectedCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Forventet beholdning (ny vare)',
                      helperText:
                          'Valgfri. Tom = behold nuværende forventet for den nye vare.',
                    ),
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => dialogNavigator.pop(),
              child: const Text('Annuller'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (selectedCategory == null || selected == null) return;
                final qty = int.tryParse(qtyCtrl.text.trim()) ?? 0;
                if (qty <= 0) return;
                final expectedText = expectedCtrl.text.trim();
                final expected = expectedText.isEmpty
                    ? null
                    : int.tryParse(expectedText);
                if (expected != null && expected < 0) return;
                if (expectedText.isNotEmpty && expected == null) return;

                try {
                  // Replace means old item should disappear from the team.
                  await widget.service.returnFromTeam(
                    fromMaterialId,
                    _team.id,
                    currentHeld,
                    'local',
                    note:
                        'Skift vare: fjern $fromLabel ($currentHeld) og tilføj ${_materialLabel(selected!)} ($qty)',
                  );
                  await widget.service.assignToTeam(
                    selected!.id,
                    _team.id,
                    qty,
                    'local',
                    note:
                        'Skift vare: fjern $fromLabel ($currentHeld) og tilføj ${_materialLabel(selected!)} ($qty)',
                  );

                  var updatedTeam = (await widget.service.listTeams())
                      .firstWhere((t) => t.id == _team.id);

                  if (expected != null) {
                    final newExpected = Map<String, int>.from(
                      updatedTeam.expectedHoldings,
                    )..[selected!.id] = expected;

                    await widget.service.updateTeam(
                      updatedTeam.copyWith(
                        expectedHoldings: newExpected,
                        updatedAt: DateTime.now(),
                      ),
                    );
                    updatedTeam = (await widget.service.listTeams()).firstWhere(
                      (t) => t.id == _team.id,
                    );
                  }

                  if (!mounted) return;
                  setState(() => _team = updatedTeam);
                  await _loadMaterials();
                  dialogNavigator.pop();
                } on TimeoutException catch (_) {
                  if (mounted) {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Tidsudløb ved rettelse af tildeling'),
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    messenger.showSnackBar(
                      SnackBar(content: Text('Kunne ikke rette tildeling: $e')),
                    );
                  }
                }
              },
              child: const Text('Gem ændring'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final materialKeys = teamMaterialIds(_team).toSet();
    final entries = materialKeys
        .map(
          (materialId) =>
              MapEntry(materialId, teamActualMaterialCount(_team, materialId)),
        )
        .toList();
    final totalAssigned = entries.fold<int>(0, (total, e) {
      return total + e.value;
    });
    final totalMissing = entries.fold<int>(0, (total, e) {
      return total + teamMissingMaterialCount(_team, e.key);
    });

    return Scaffold(
      appBar: AppBar(
        title: Text('Hold: ${_team.name}'),
        actions: [
          if (widget.canManageTeamMaterials)
            IconButton(
              icon: const Icon(Icons.insights_outlined),
              tooltip: 'Rapport for perioden',
              onPressed: _showTeamLossReport,
            ),
        ],
      ),
      floatingActionButton: widget.canManageTeamMaterials
          ? FloatingActionButton(
              onPressed: _assignMaterial,
              child: const Icon(Icons.add),
            )
          : null,
      body: entries.isEmpty
          ? const Center(child: Text('Ingen materialer tildelt endnu.'))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          Chip(
                            avatar: const Icon(Icons.inventory_2, size: 18),
                            label: Text('Materialer: ${entries.length}'),
                          ),
                          Chip(
                            avatar: const Icon(Icons.numbers, size: 18),
                            label: Text('Tildelt i alt: $totalAssigned'),
                          ),
                          Chip(
                            avatar: const Icon(Icons.report_problem, size: 18),
                            label: Text('Mangler i alt: $totalMissing'),
                            backgroundColor: totalMissing > 0
                                ? Colors.red.shade50
                                : Colors.green.shade50,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.of(context).padding.bottom + 88,
                    ),
                    children: [
                      ..._buildStructuredHoldings(entries),
                      _buildKitSetsSection(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
