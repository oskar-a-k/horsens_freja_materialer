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
        _teams = teams;
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

      final isAdmin = userData?['isAdmin'] as bool? ?? false;
      final role = (userData?['role'] as String? ?? '').trim().toLowerCase();
      final canManage =
          hasOverrideAdmin || isAdmin || _materialManagerRoles.contains(role);

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

      final teamLocked = !canManage && assignedTeamIds.isNotEmpty;
      final visibleTeams = teamLocked
          ? teams.where((team) => assignedTeamIds.contains(team.id)).toList()
          : teams;

      if (!mounted) return;
      setState(() {
        _canManageTeamMaterials = canManage;
        _teams = visibleTeams;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _canManageTeamMaterials = hasOverrideAdmin;
        _teams = hasOverrideAdmin ? teams : <TeamModel>[];
      });
    }
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
                              needsMedicalBag: needsMedicalBag,
                            );
                            await _service
                                .createTeam(team)
                                .timeout(const Duration(seconds: 8));
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
                    await _service.updateTeam(
                      team.copyWith(
                        name: name,
                        needsMedicalBag: needsMedicalBag,
                      ),
                    );
                    await _loadAll();
                    if (!mounted) return;
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
    return Scaffold(
      appBar: AppBar(title: const Text('Hold')),
      floatingActionButton: _canManageTeamMaterials
          ? FloatingActionButton(
              onPressed: _addTeam,
              child: const Icon(Icons.add),
            )
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
                : ListView.builder(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.of(context).padding.bottom + 88,
                    ),
                    itemCount: _teams
                        .where(
                          (t) => t.name.toLowerCase().contains(_teamSearch),
                        )
                        .length,
                    itemBuilder: (context, index) {
                      final filtered = _teams
                          .where(
                            (t) => t.name.toLowerCase().contains(_teamSearch),
                          )
                          .toList();
                      final team = filtered[index];
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
                              if (_canManageTeamMaterials)
                                IconButton(
                                  icon: const Icon(Icons.edit),
                                  onPressed: () => _editTeam(team),
                                ),
                              if (_canManageTeamMaterials)
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
                  ),
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
      final isExpanded = _categoryExpanded.putIfAbsent(category, () => true);
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
              final actual = entry.value;
              final expected = _team.expectedHoldings[entry.key];
              final missing = expected == null ? null : (expected - actual);

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
                          IconButton(
                            icon: const Icon(Icons.assignment_turned_in),
                            tooltip: 'Indmeld status',
                            onPressed: () => _reportMaterialStatus(entry.key),
                          ),
                          if (widget.canManageTeamMaterials)
                            IconButton(
                              icon: const Icon(Icons.flag_outlined),
                              tooltip: 'Sæt forventet beholdning',
                              onPressed: () => _setExpectedHolding(entry.key),
                            ),
                          if (widget.canManageTeamMaterials)
                            IconButton(
                              icon: const Icon(Icons.swap_horiz),
                              tooltip: 'Ret tildeling (skift vare)',
                              onPressed: () =>
                                  _replaceAssignedMaterial(entry.key),
                            ),
                          if (widget.canManageTeamMaterials)
                            IconButton(
                              icon: const Icon(Icons.undo),
                              tooltip: 'Returner materiale',
                              onPressed: () => _returnMaterial(entry.key),
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
    final jerseySizeCtrl = TextEditingController(
      text: existing?.jerseySize ?? '',
    );
    final shortsSizeCtrl = TextEditingController(
      text: existing?.shortsSize ?? '',
    );
    final socksSizeCtrl = TextEditingController(
      text: existing?.socksSize ?? '',
    );
    final noteCtrl = TextEditingController(text: existing?.note ?? '');
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
                      jerseySize: jerseySizeCtrl.text.trim(),
                      jerseyStatus: jerseyStatus,
                      shortsSize: shortsSizeCtrl.text.trim(),
                      shortsStatus: shortsStatus,
                      socksSize: socksSizeCtrl.text.trim(),
                      socksStatus: socksStatus,
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
                if (widget.canManageTeamMaterials)
                  TextButton.icon(
                    onPressed: () => _showKitSetDialog(),
                    icon: const Icon(Icons.add),
                    label: const Text('Tilføj sæt'),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Hvert sæt indeholder trøje, shorts, strømper og duffelbag som separate dele.',
            ),
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
                                'Trøje: ${_kitSizeLabel(kitSet.jerseySize)} · ${_kitStatusLabel(kitSet.jerseyStatus)}',
                              ),
                            ),
                            Chip(
                              label: Text(
                                'Shorts: ${_kitSizeLabel(kitSet.shortsSize)} · ${_kitStatusLabel(kitSet.shortsStatus)}',
                              ),
                            ),
                            Chip(
                              label: Text(
                                'Strømper: ${_kitSizeLabel(kitSet.socksSize)} · ${_kitStatusLabel(kitSet.socksStatus)}',
                              ),
                            ),
                            Chip(
                              label: Text(
                                'Duffelbag: ${_kitStatusLabel(kitSet.duffelbagStatus)}',
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

  Future<void> _setExpectedHolding(String materialId) async {
    if (!widget.canManageTeamMaterials) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Kun admin og materialforvalter kan sætte forventet beholdning.',
          ),
        ),
      );
      return;
    }

    final currentExpected = _team.expectedHoldings[materialId];
    final currentActual = _team.holdings[materialId] ?? 0;
    final expectedCtrl = TextEditingController(
      text: (currentExpected ?? currentActual).toString(),
    );

    await showDialog(
      context: context,
      builder: (context) {
        final dialogNavigator = Navigator.of(context);
        final messenger = ScaffoldMessenger.of(context);
        return AlertDialog(
          title: const Text('Forventet beholdning'),
          content: TextField(
            controller: expectedCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Forventet antal'),
          ),
          actions: [
            TextButton(
              onPressed: () => dialogNavigator.pop(),
              child: const Text('Annuller'),
            ),
            ElevatedButton(
              onPressed: () async {
                final expected = int.tryParse(expectedCtrl.text.trim());
                if (expected == null || expected < 0) return;

                final newExpected = Map<String, int>.from(
                  _team.expectedHoldings,
                )..[materialId] = expected;

                try {
                  final updatedTeam = _team.copyWith(
                    expectedHoldings: newExpected,
                    updatedAt: DateTime.now(),
                  );
                  await widget.service
                      .updateTeam(updatedTeam)
                      .timeout(const Duration(seconds: 8));
                  final refreshed = (await widget.service.listTeams())
                      .firstWhere((t) => t.id == _team.id);
                  if (!mounted) return;
                  setState(() => _team = refreshed);
                  dialogNavigator.pop();
                } on TimeoutException catch (_) {
                  if (mounted) {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Tidsudløb ved gem af forventet beholdning',
                        ),
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text('Kunne ikke gemme forventet antal: $e'),
                      ),
                    );
                  }
                }
              },
              child: const Text('Gem'),
            ),
          ],
        );
      },
    );
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
                    ..sort();

              final filtered = _materials.where((m) {
                final categoryName = m.category.trim().isEmpty
                    ? 'Ukendt'
                    : m.category;
                if (selectedCategory == null ||
                    categoryName != selectedCategory) {
                  return false;
                }
                final label = ('${m.name} ${m.variant ?? ''}').toLowerCase();
                return materialSearch.isEmpty || label.contains(materialSearch);
              }).toList();

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

  Future<void> _returnMaterial(String materialId) async {
    if (!widget.canManageTeamMaterials) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Kun admin og materialforvalter kan flytte materialer.',
          ),
        ),
      );
      return;
    }

    final qtyCtrl = TextEditingController(text: '1');
    await showDialog(
      context: context,
      builder: (context) {
        final dialogNavigator = Navigator.of(context);
        return AlertDialog(
          title: const Text('Returner materiale'),
          content: TextField(
            controller: qtyCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Antal'),
          ),
          actions: [
            TextButton(
              onPressed: () => dialogNavigator.pop(),
              child: const Text('Annuller'),
            ),
            ElevatedButton(
              onPressed: () async {
                final qty = int.tryParse(qtyCtrl.text) ?? 0;
                if (qty <= 0) return;
                await widget.service.returnFromTeam(
                  materialId,
                  _team.id,
                  qty,
                  'local',
                );
                final updatedTeam = (await widget.service.listTeams())
                    .firstWhere((t) => t.id == _team.id);
                setState(() => _team = updatedTeam);
                await _loadMaterials();
                if (!mounted) return;
                dialogNavigator.pop();
              },
              child: const Text('Returner'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _reportMaterialStatus(String materialId) async {
    final material = _materialForId(materialId);
    final materialLabel = _materialLabel(material);
    final currentStatus = _team.holdings[materialId] ?? 0;
    final expected = _team.expectedHoldings[materialId];
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

                  if (!mounted) return;
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        missing > 0
                            ? 'Status gemt. Mangelsag er oprettet/opdateret.'
                            : 'Status gemt.',
                      ),
                    ),
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

    final currentHeld = _team.holdings[fromMaterialId] ?? 0;
    if (currentHeld <= 0) return;

    final qtyCtrl = TextEditingController(text: currentHeld.toString());
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
                    ..sort();

              final filtered = _materials.where((m) {
                if (m.id == fromMaterialId) return false;
                final categoryName = m.category.trim().isEmpty
                    ? 'Ukendt'
                    : m.category;
                if (selectedCategory == null ||
                    categoryName != selectedCategory) {
                  return false;
                }
                final label = ('${m.name} ${m.variant ?? ''}').toLowerCase();
                return materialSearch.isEmpty || label.contains(materialSearch);
              }).toList();

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
                    onChanged: (v) => setStateDialog(() => selected = v),
                  ),
                  TextField(
                    controller: qtyCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Antal der skal flyttes',
                      helperText: 'Maks: $currentHeld',
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
                if (qty <= 0 || qty > currentHeld) return;
                if (selected!.totalInStock < qty) {
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Der er ikke nok på lager af den nye vare.',
                      ),
                    ),
                  );
                  return;
                }

                try {
                  await widget.service.returnFromTeam(
                    fromMaterialId,
                    _team.id,
                    qty,
                    'local',
                    note:
                        'Ret tildeling: $fromLabel -> ${_materialLabel(selected!)}',
                  );
                  await widget.service.assignToTeam(
                    selected!.id,
                    _team.id,
                    qty,
                    'local',
                    note:
                        'Ret tildeling: $fromLabel -> ${_materialLabel(selected!)}',
                  );

                  final updatedTeam = (await widget.service.listTeams())
                      .firstWhere((t) => t.id == _team.id);

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
    final entries = _team.holdings.entries.toList();
    final totalAssigned = entries.fold<int>(0, (total, e) => total + e.value);
    final totalMissing = entries.fold<int>(0, (total, e) {
      final expected = _team.expectedHoldings[e.key];
      if (expected == null) return total;
      return total + (expected - e.value);
    });

    return Scaffold(
      appBar: AppBar(title: Text('Hold: ${_team.name}')),
      floatingActionButton: widget.canManageTeamMaterials
          ? FloatingActionButton(
              onPressed: _assignMaterial,
              child: const Icon(Icons.add),
            )
          : null,
      body: _team.holdings.isEmpty
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
