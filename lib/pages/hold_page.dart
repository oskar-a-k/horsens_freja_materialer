import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/team_model.dart';
import '../models/material_model.dart';
import '../services/inventory_service.dart';

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
    _loadAccess();
  }

  Future<void> _loadAccess() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      if (!mounted) return;
      setState(() => _canManageTeamMaterials = false);
      return;
    }

    final currentEmail = currentUser.email?.toLowerCase();
    final hasOverrideAdmin =
        currentEmail != null && _adminOverrideEmails.contains(currentEmail);

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();

      final isAdmin = snapshot.data()?['isAdmin'] as bool? ?? false;
      final role = (snapshot.data()?['role'] as String? ?? '')
          .trim()
          .toLowerCase();
      final canManage =
          hasOverrideAdmin || isAdmin || _materialManagerRoles.contains(role);

      if (!mounted) return;
      setState(() => _canManageTeamMaterials = canManage);
    } catch (_) {
      if (!mounted) return;
      setState(() => _canManageTeamMaterials = hasOverrideAdmin);
    }
  }

  Future<void> _loadAll() async {
    final teams = await _service.listTeams();
    setState(() {
      _teams = teams;
    });
  }

  Future<void> _addTeam() async {
    final nameCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) {
        var loading = false;
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final messenger = ScaffoldMessenger.of(context);
            final dialogNavigator = Navigator.of(context);
            return AlertDialog(
              title: const Text('Tilføj hold'),
              content: TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Holdnavn'),
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
        final dialogNavigator = Navigator.of(context);
        return AlertDialog(
          title: const Text('Rediger hold'),
          content: TextField(
            controller: nameCtrl,
            decoration: const InputDecoration(labelText: 'Holdnavn'),
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
                await _service.updateTeam(team.copyWith(name: name));
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
                            '${team.holdings.length} forskellige materialer',
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
                          if (widget.canManageTeamMaterials)
                            IconButton(
                              icon: const Icon(Icons.flag_outlined),
                              tooltip: 'Sæt forventet beholdning',
                              onPressed: () => _setExpectedHolding(entry.key),
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
                    children: _buildStructuredHoldings(entries),
                  ),
                ),
              ],
            ),
    );
  }
}
