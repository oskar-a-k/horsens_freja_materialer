import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/material_model.dart';
import '../models/team_model.dart';
import '../services/inventory_service.dart';

class LagerPage extends StatefulWidget {
  final InventoryService service;

  const LagerPage({super.key, required this.service});

  @override
  State<LagerPage> createState() => _LagerPageState();
}

class _LagerPageState extends State<LagerPage> {
  late final InventoryService _service;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<MaterialModel> _materials = [];
  List<TeamModel> _teams = [];
  Map<String, int> _medicalBagTemplate = {};
  String _searchQuery = '';
  String _selectedCategory = 'Alle';
  final Set<String> _expandedCategories = <String>{};

  @override
  void initState() {
    super.initState();
    _service = widget.service;
    _loadInventoryData();
  }

  Future<void> _loadInventoryData() async {
    final materialsFuture = _service.listMaterials();
    final teamsFuture = _service.listTeams();
    final templateFuture = _loadMedicalBagTemplate();
    final list = await materialsFuture;
    final teams = await teamsFuture;
    final template = await templateFuture;
    if (!mounted) return;
    setState(() {
      _materials = list;
      _teams = teams;
      _medicalBagTemplate = template;
    });
  }

  bool _isMedicalBagCategory(String category) {
    final c = category.toLowerCase();
    return c.contains('læge') || c.contains('laege');
  }

  Future<Map<String, int>> _loadMedicalBagTemplate() async {
    final snapshot = await _firestore
        .collection('app_settings')
        .doc('medical_bag_template')
        .get();
    final data = snapshot.data();
    if (data == null) return const <String, int>{};

    final rawItems = data['items'] as Map<String, dynamic>?;
    if (rawItems == null || rawItems.isEmpty) return const <String, int>{};

    final parsed = <String, int>{};
    rawItems.forEach((key, value) {
      final qty = (value as num?)?.toInt() ?? 0;
      if (qty > 0) {
        parsed[key] = qty;
      }
    });
    return parsed;
  }

  Future<void> _saveMedicalBagTemplate(Map<String, int> items) async {
    await _firestore.collection('app_settings').doc('medical_bag_template').set(
      {'items': items, 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }

  int _loanedCount(String materialId) {
    var count = 0;
    for (final team in _teams) {
      count += team.holdings[materialId] ?? 0;
    }
    return count;
  }

  List<MapEntry<TeamModel, int>> _teamsWithMaterial(String materialId) {
    final result = <MapEntry<TeamModel, int>>[];
    for (final team in _teams) {
      final qty = team.holdings[materialId] ?? 0;
      if (qty > 0) {
        result.add(MapEntry(team, qty));
      }
    }
    result.sort(
      (a, b) => a.key.name.toLowerCase().compareTo(b.key.name.toLowerCase()),
    );
    return result;
  }

  Future<void> _showTeamsForMaterial(MaterialModel material) async {
    final entries = _teamsWithMaterial(material.id);
    final displayName = material.variant == null || material.variant!.isEmpty
        ? material.name
        : '${material.name} · ${material.variant}';

    await showDialog<void>(
      context: context,
      builder: (context) {
        final dialogNavigator = Navigator.of(context);
        return AlertDialog(
          title: Text('Udleveret til hold\n$displayName'),
          content: SizedBox(
            width: 420,
            child: entries.isEmpty
                ? const Text('Ingen hold har denne vare udleveret lige nu.')
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: entries.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final team = entries[index].key;
                      final qty = entries[index].value;
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(team.name),
                        trailing: Text(
                          '$qty ${material.unit}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      );
                    },
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
  }

  List<String> _categoryOptions() {
    final categories =
        _materials
            .map((m) => m.category.trim())
            .where((c) => c.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return categories;
  }

  Widget _buildCategoryInput(
    TextEditingController categoryCtrl, {
    VoidCallback? onChanged,
  }) {
    final categories = _categoryOptions();
    final current = categoryCtrl.text.trim();
    final selected = current.isEmpty || !categories.contains(current)
        ? null
        : current;

    return Column(
      children: [
        DropdownButtonFormField<String>(
          initialValue: selected,
          decoration: const InputDecoration(labelText: 'Vælg kategori'),
          isExpanded: true,
          items: categories
              .map((c) => DropdownMenuItem<String>(value: c, child: Text(c)))
              .toList(),
          onChanged: (v) {
            if (v == null) return;
            categoryCtrl.text = v;
            onChanged?.call();
          },
        ),
        TextField(
          controller: categoryCtrl,
          decoration: const InputDecoration(
            labelText: 'Eller skriv ny kategori',
          ),
          onChanged: (_) => onChanged?.call(),
        ),
      ],
    );
  }

  Future<void> _addMaterial() async {
    final productCtrl = TextEditingController();
    final variantCtrl = TextEditingController();
    final categoryCtrl = TextEditingController();
    final unitCtrl = TextEditingController(text: 'stk');
    final stockCtrl = TextEditingController(text: '0');
    final minCtrl = TextEditingController(text: '0');
    final standardQtyCtrl = TextEditingController(text: '1');

    await showDialog(
      context: context,
      builder: (context) {
        final dialogNavigator = Navigator.of(context);
        final messenger = ScaffoldMessenger.of(context);
        var includeInMedicalStandard = false;
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final isMedicalCategory = _isMedicalBagCategory(
              categoryCtrl.text.trim(),
            );
            if (!isMedicalCategory) {
              includeInMedicalStandard = false;
            }

            return AlertDialog(
              title: const Text('Tilføj ny vare'),
              content: SingleChildScrollView(
                child: Column(
                  children: [
                    _buildCategoryInput(
                      categoryCtrl,
                      onChanged: () => setStateDialog(() {}),
                    ),
                    TextField(
                      controller: productCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Vare (f.eks. Hummel)',
                      ),
                    ),
                    TextField(
                      controller: variantCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Variant (f.eks. No 3)',
                      ),
                    ),
                    TextField(
                      controller: unitCtrl,
                      decoration: const InputDecoration(labelText: 'Enhed'),
                    ),
                    TextField(
                      controller: stockCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Start beholdning',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    TextField(
                      controller: minCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Min. advarsel',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    if (isMedicalCategory) ...[
                      const SizedBox(height: 8),
                      SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Standard-vare i lægetaske'),
                        value: includeInMedicalStandard,
                        onChanged: (value) {
                          setStateDialog(() {
                            includeInMedicalStandard = value;
                          });
                        },
                      ),
                      if (includeInMedicalStandard)
                        TextField(
                          controller: standardQtyCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Standard antal i lægetaske',
                          ),
                        ),
                    ],
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
                    final product = productCtrl.text.trim();
                    final variant = variantCtrl.text.trim();
                    if (product.isEmpty) return;
                    final material = MaterialModel(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      name: product,
                      variant: variant.isEmpty ? null : variant,
                      sku: null,
                      category: categoryCtrl.text.trim(),
                      unit: unitCtrl.text.trim(),
                      totalInStock: int.tryParse(stockCtrl.text) ?? 0,
                      minThreshold: int.tryParse(minCtrl.text) ?? 0,
                    );
                    try {
                      await _service
                          .createMaterial(material)
                          .timeout(const Duration(seconds: 8));

                      if (includeInMedicalStandard) {
                        final standardQty =
                            int.tryParse(standardQtyCtrl.text.trim()) ?? 0;
                        final template = Map<String, int>.from(
                          _medicalBagTemplate,
                        );
                        if (standardQty > 0) {
                          template[material.id] = standardQty;
                        } else {
                          template.remove(material.id);
                        }
                        await _saveMedicalBagTemplate(template);
                      }

                      await _loadInventoryData();
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
                              'Kunne ikke oprette vare: ${e.toString()}',
                            ),
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
      },
    );
  }

  Future<void> _adjustStock(MaterialModel material) async {
    final qtyCtrl = TextEditingController(text: '0');
    final noteCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) {
        final dialogNavigator = Navigator.of(context);
        final messenger = ScaffoldMessenger.of(context);
        return AlertDialog(
          title: Text('Justér lager: ${material.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: qtyCtrl,
                decoration: const InputDecoration(
                  labelText: 'Delta (brug - for fjernelse)',
                ),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(labelText: 'Noter (valgfri)'),
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
                final delta = int.tryParse(qtyCtrl.text) ?? 0;
                if (delta == 0) return;
                try {
                  await _service
                      .adjustStock(
                        material.id,
                        delta,
                        'local',
                        note: noteCtrl.text.trim(),
                      )
                      .timeout(const Duration(seconds: 8));
                  await _loadInventoryData();
                  if (!mounted) return;
                  dialogNavigator.pop();
                } on TimeoutException catch (_) {
                  if (mounted) {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Tidsudløb ved opdatering (Firestore svarer ikke)',
                        ),
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          'Kunne ikke opdatere lager: ${e.toString()}',
                        ),
                      ),
                    );
                  }
                }
              },
              child: const Text('Opdater'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _editMaterial(MaterialModel material) async {
    final onLoan = _loanedCount(material.id);
    final currentTotal = material.totalInStock + onLoan;
    final categoryCtrl = TextEditingController(text: material.category);
    final productCtrl = TextEditingController(text: material.name);
    final variantCtrl = TextEditingController(text: material.variant ?? '');
    final unitCtrl = TextEditingController(text: material.unit);
    final totalCtrl = TextEditingController(text: currentTotal.toString());
    final minCtrl = TextEditingController(
      text: material.minThreshold.toString(),
    );
    var includeInMedicalStandard = (_medicalBagTemplate[material.id] ?? 0) > 0;
    final standardQtyCtrl = TextEditingController(
      text:
          ((_medicalBagTemplate[material.id] ?? 1) <= 0
                  ? 1
                  : (_medicalBagTemplate[material.id] ?? 1))
              .toString(),
    );

    await showDialog(
      context: context,
      builder: (context) {
        final dialogNavigator = Navigator.of(context);
        final messenger = ScaffoldMessenger.of(context);
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final isMedicalCategory = _isMedicalBagCategory(
              categoryCtrl.text.trim(),
            );
            if (!isMedicalCategory) {
              includeInMedicalStandard = false;
            }

            return AlertDialog(
              title: const Text('Redigér vare'),
              content: SingleChildScrollView(
                child: Column(
                  children: [
                    _buildCategoryInput(
                      categoryCtrl,
                      onChanged: () => setStateDialog(() {}),
                    ),
                    TextField(
                      controller: productCtrl,
                      decoration: const InputDecoration(labelText: 'Vare'),
                    ),
                    TextField(
                      controller: variantCtrl,
                      decoration: const InputDecoration(labelText: 'Variant'),
                    ),
                    TextField(
                      controller: unitCtrl,
                      decoration: const InputDecoration(labelText: 'Enhed'),
                    ),
                    TextField(
                      controller: totalCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Total beholdning',
                        helperText:
                            'På lager beregnes automatisk ud fra udlån.',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    TextField(
                      controller: minCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Min. advarsel',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    if (isMedicalCategory) ...[
                      const SizedBox(height: 8),
                      SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Standard-vare i lægetaske'),
                        value: includeInMedicalStandard,
                        onChanged: (value) {
                          setStateDialog(() {
                            includeInMedicalStandard = value;
                          });
                        },
                      ),
                      if (includeInMedicalStandard)
                        TextField(
                          controller: standardQtyCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Standard antal i lægetaske',
                          ),
                        ),
                    ],
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
                    final product = productCtrl.text.trim();
                    if (product.isEmpty) return;

                    final wantedTotal =
                        int.tryParse(totalCtrl.text.trim()) ?? currentTotal;
                    final recalculatedOnStock = wantedTotal - onLoan;

                    final updated = material.copyWith(
                      category: categoryCtrl.text.trim(),
                      name: product,
                      variant: variantCtrl.text.trim().isEmpty
                          ? null
                          : variantCtrl.text.trim(),
                      unit: unitCtrl.text.trim().isEmpty
                          ? material.unit
                          : unitCtrl.text.trim(),
                      totalInStock: recalculatedOnStock,
                      minThreshold:
                          int.tryParse(minCtrl.text.trim()) ??
                          material.minThreshold,
                      updatedAt: DateTime.now(),
                    );

                    try {
                      await _service
                          .updateMaterial(updated)
                          .timeout(const Duration(seconds: 8));

                      final template = Map<String, int>.from(
                        _medicalBagTemplate,
                      );
                      if (includeInMedicalStandard && isMedicalCategory) {
                        final standardQty =
                            int.tryParse(standardQtyCtrl.text.trim()) ?? 0;
                        if (standardQty > 0) {
                          template[material.id] = standardQty;
                        } else {
                          template.remove(material.id);
                        }
                      } else {
                        template.remove(material.id);
                      }
                      await _saveMedicalBagTemplate(template);

                      await _loadInventoryData();
                      if (!mounted) return;
                      dialogNavigator.pop();
                    } on TimeoutException catch (_) {
                      if (mounted) {
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Tidsudløb ved opdatering (Firestore svarer ikke)',
                            ),
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              'Kunne ikke gemme ændringer: ${e.toString()}',
                            ),
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
      },
    );
  }

  int _expectedCount(String materialId) {
    var count = 0;
    for (final team in _teams) {
      count += team.expectedHoldings[materialId] ?? 0;
    }
    return count;
  }

  Future<void> _deleteMaterial(MaterialModel material) async {
    final onLoan = _loanedCount(material.id);
    final expected = _expectedCount(material.id);
    final messenger = ScaffoldMessenger.of(context);

    if (onLoan > 0 || expected > 0) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Varen kan ikke slettes endnu. Udlån: $onLoan · Forventet på hold: $expected',
          ),
        ),
      );
      return;
    }

    final displayName = material.variant == null || material.variant!.isEmpty
        ? material.name
        : '${material.name} · ${material.variant}';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final dialogNavigator = Navigator.of(context);
        return AlertDialog(
          title: const Text('Slet vare'),
          content: Text('Vil du slette "$displayName" fra lageret?'),
          actions: [
            TextButton(
              onPressed: () => dialogNavigator.pop(false),
              child: const Text('Annuller'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => dialogNavigator.pop(true),
              child: const Text('Slet'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await _service
          .deleteMaterial(material.id)
          .timeout(const Duration(seconds: 8));
      await _loadInventoryData();
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Varen er slettet.')),
      );
    } on TimeoutException catch (_) {
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Tidsudløb ved sletning (Firestore svarer ikke)'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Kunne ikke slette vare: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lager')),
      floatingActionButton: FloatingActionButton(
        onPressed: _addMaterial,
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Søg efter vare eller variant',
                    ),
                    onChanged: (v) =>
                        setState(() => _searchQuery = v.trim().toLowerCase()),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _selectedCategory,
                  items: _buildCategoryDropdownItems(),
                  onChanged: (v) =>
                      setState(() => _selectedCategory = v ?? 'Alle'),
                ),
              ],
            ),
          ),
          Expanded(
            child: _materials.isEmpty
                ? const Center(
                    child: Text(
                      'Intet materiale endnu. Tryk + for at tilføje.',
                    ),
                  )
                : ListView(children: _buildCategoryList()),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildCategoryList() {
    // group by category -> product -> variants, with filters
    final Map<String, Map<String, List<MaterialModel>>> grouped = {};
    for (final m in _materials) {
      final catName = m.category.isEmpty ? 'Ukendt' : m.category;
      if (_selectedCategory != 'Alle' && catName != _selectedCategory) continue;
      final searchField = ('${m.name} ${m.variant ?? ''} ${m.category}')
          .toLowerCase();
      if (_searchQuery.isNotEmpty && !searchField.contains(_searchQuery)) {
        continue;
      }

      final prod = m.name;
      grouped.putIfAbsent(catName, () => {});
      final prodMap = grouped[catName]!;
      prodMap.putIfAbsent(prod, () => []);
      prodMap[prod]!.add(m);
    }

    final List<Widget> widgets = [];
    grouped.forEach((cat, prodMap) {
      // compute low-stock count for category
      int catLowCount = 0;
      for (final variants in prodMap.values) {
        for (final v in variants) {
          if (v.minThreshold > 0 && v.totalInStock <= v.minThreshold) {
            catLowCount++;
          }
        }
      }

      final products = <Widget>[];
      prodMap.forEach((prod, variants) {
        final prodLow = variants
            .where(
              (v) => v.minThreshold > 0 && v.totalInStock <= v.minThreshold,
            )
            .length;
        products.add(
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: ExpansionTile(
              title: Text(prod),
              subtitle: Text(
                '${variants.length} varianter${prodLow > 0 ? ' · $prodLow lave' : ''}',
              ),
              children: variants.map((v) {
                final displayName = v.variant == null || v.variant!.isEmpty
                    ? prod
                    : '$prod · ${v.variant}';
                final onLoan = _loanedCount(v.id);
                final onStock = v.totalInStock;
                final total = onStock + onLoan;
                final isLow =
                    v.minThreshold > 0 && v.totalInStock <= v.minThreshold;
                final isMedical = _isMedicalBagCategory(v.category);
                final standardQty = _medicalBagTemplate[v.id] ?? 0;
                return ListTile(
                  title: Text(displayName),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          Chip(
                            label: Text('Total: $total'),
                            visualDensity: VisualDensity.compact,
                          ),
                          Chip(
                            label: Text('Udlån: $onLoan'),
                            visualDensity: VisualDensity.compact,
                          ),
                          Chip(
                            label: Text(
                              'PÅ LAGER: $onStock ${v.unit}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            backgroundColor: onStock > 0
                                ? Colors.green.shade100
                                : Colors.red.shade100,
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                      if (isMedical)
                        Text(
                          standardQty > 0
                              ? 'Lægetaske standard: Ja ($standardQty ${v.unit})'
                              : 'Lægetaske standard: Nej',
                          style: TextStyle(
                            color: standardQty > 0
                                ? Colors.green.shade700
                                : Colors.grey.shade700,
                            fontWeight: standardQty > 0
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${v.totalInStock}',
                        style: TextStyle(
                          color: isLow ? Colors.red : null,
                          fontWeight: isLow ? FontWeight.bold : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (isLow) const Icon(Icons.warning, color: Colors.red),
                      IconButton(
                        icon: const Icon(Icons.groups_2_outlined),
                        tooltip: 'Vis hold med udleveret vare',
                        onPressed: () => _showTeamsForMaterial(v),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_note),
                        tooltip: 'Redigér vare',
                        onPressed: () => _editMaterial(v),
                      ),
                      IconButton(
                        icon: const Icon(Icons.tune),
                        tooltip: 'Juster lager',
                        onPressed: () => _adjustStock(v),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Slet vare',
                        onPressed: () => _deleteMaterial(v),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        );
      });

      widgets.add(
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ExpansionTile(
            key: PageStorageKey<String>('category-$cat'),
            initiallyExpanded: _expandedCategories.contains(cat),
            onExpansionChanged: (expanded) {
              setState(() {
                if (expanded) {
                  _expandedCategories.add(cat);
                } else {
                  _expandedCategories.remove(cat);
                }
              });
            },
            title: Text(
              cat,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            trailing: catLowCount > 0
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.warning, color: Colors.red),
                      const SizedBox(width: 6),
                      Text(
                        '$catLowCount lave',
                        style: const TextStyle(color: Colors.red),
                      ),
                    ],
                  )
                : null,
            children: products,
          ),
        ),
      );
    });
    return widgets;
  }

  List<DropdownMenuItem<String>> _buildCategoryDropdownItems() {
    final cats = <String>{'Alle'};
    for (final m in _materials) {
      cats.add(m.category.isEmpty ? 'Ukendt' : m.category);
    }
    final sorted = cats.toList()..sort();
    return sorted
        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
        .toList();
  }
}
