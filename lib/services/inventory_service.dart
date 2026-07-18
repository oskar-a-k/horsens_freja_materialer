import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/material_model.dart';
import '../models/team_model.dart';
import '../models/transaction_model.dart';

abstract class InventoryService {
  Future<MaterialModel> createMaterial(MaterialModel material);
  Future<void> updateMaterial(MaterialModel material);
  Future<void> deleteMaterial(String materialId);
  Future<List<MaterialModel>> listMaterials();

  Future<TeamModel> createTeam(TeamModel team);
  Future<void> updateTeam(TeamModel team);
  Future<void> deleteTeam(String teamId);
  Future<List<TeamModel>> listTeams();

  Future<void> assignToTeam(
    String materialId,
    String teamId,
    int quantity,
    String performedBy, {
    String? note,
  });

  Future<void> returnFromTeam(
    String materialId,
    String teamId,
    int quantity,
    String performedBy, {
    String? note,
  });

  Future<void> adjustStock(
    String materialId,
    int delta,
    String performedBy, {
    String? note,
  });

  Future<List<TransactionModel>> getTransactions({
    String? materialId,
    String? teamId,
  });
}

class InMemoryInventoryService implements InventoryService {
  final Map<String, MaterialModel> _materials = {};
  final Map<String, TeamModel> _teams = {};
  final List<TransactionModel> _transactions = [];

  bool _initialized = false;
  Future<void>? _initFuture;

  int _txCounter = 0;

  @override
  Future<MaterialModel> createMaterial(MaterialModel material) async {
    await _ensureInit();
    _materials[material.id] = material;
    await _saveAll();
    return material;
  }

  @override
  Future<void> updateMaterial(MaterialModel material) async {
    await _ensureInit();
    final existing = _materials[material.id];
    if (existing == null) throw StateError('Material not found');
    _materials[material.id] = material;
    await _saveAll();
  }

  @override
  Future<void> deleteMaterial(String materialId) async {
    await _ensureInit();
    _materials.remove(materialId);
    await _saveAll();
  }

  @override
  Future<List<MaterialModel>> listMaterials() async {
    await _ensureInit();
    return _materials.values.toList();
  }

  @override
  Future<TeamModel> createTeam(TeamModel team) async {
    await _ensureInit();
    _teams[team.id] = team;
    await _saveAll();
    return team;
  }

  @override
  Future<void> updateTeam(TeamModel team) async {
    await _ensureInit();
    final existing = _teams[team.id];
    if (existing == null) throw StateError('Team not found');
    _teams[team.id] = team;
    await _saveAll();
  }

  @override
  Future<void> deleteTeam(String teamId) async {
    await _ensureInit();
    _teams.remove(teamId);
    await _saveAll();
  }

  @override
  Future<List<TeamModel>> listTeams() async {
    await _ensureInit();
    return _teams.values.toList();
  }

  String _nextTxId() {
    _txCounter += 1;
    return DateTime.now().millisecondsSinceEpoch.toString() + '-$_txCounter';
  }

  @override
  Future<void> assignToTeam(
    String materialId,
    String teamId,
    int quantity,
    String performedBy, {
    String? note,
  }) async {
    await _ensureInit();
    final material = _materials[materialId];
    final team = _teams[teamId];
    if (material == null) throw StateError('Material not found');
    if (team == null) throw StateError('Team not found');
    final updatedMaterial = material.copyWith(
      totalInStock: material.totalInStock - quantity,
    );
    _materials[materialId] = updatedMaterial;

    final newHoldings = Map<String, int>.from(team.holdings);
    newHoldings[materialId] = (newHoldings[materialId] ?? 0) + quantity;
    final updatedTeam = team.copyWith(holdings: newHoldings);
    _teams[teamId] = updatedTeam;

    final tx = TransactionModel(
      id: _nextTxId(),
      materialId: materialId,
      type: 'assign_to_team',
      quantity: quantity,
      teamId: teamId,
      performedBy: performedBy,
      note: note,
      timestamp: DateTime.now(),
    );
    _transactions.add(tx);
    await _saveAll();
  }

  @override
  Future<void> returnFromTeam(
    String materialId,
    String teamId,
    int quantity,
    String performedBy, {
    String? note,
  }) async {
    await _ensureInit();
    final material = _materials[materialId];
    final team = _teams[teamId];
    if (material == null) throw StateError('Material not found');
    if (team == null) throw StateError('Team not found');

    final currentHeld = team.holdings[materialId] ?? 0;
    final toReturn = quantity > currentHeld ? currentHeld : quantity;

    final updatedMaterial = material.copyWith(
      totalInStock: material.totalInStock + toReturn,
    );
    _materials[materialId] = updatedMaterial;

    final newHoldings = Map<String, int>.from(team.holdings);
    final remaining = (newHoldings[materialId] ?? 0) - toReturn;
    if (remaining <= 0) {
      newHoldings.remove(materialId);
    } else {
      newHoldings[materialId] = remaining;
    }
    final updatedTeam = team.copyWith(holdings: newHoldings);
    _teams[teamId] = updatedTeam;

    final tx = TransactionModel(
      id: _nextTxId(),
      materialId: materialId,
      type: 'return_from_team',
      quantity: toReturn,
      teamId: teamId,
      performedBy: performedBy,
      note: note,
      timestamp: DateTime.now(),
    );
    _transactions.add(tx);
    await _saveAll();
  }

  @override
  Future<void> adjustStock(
    String materialId,
    int delta,
    String performedBy, {
    String? note,
  }) async {
    await _ensureInit();
    final material = _materials[materialId];
    if (material == null) throw StateError('Material not found');
    final newStock = material.totalInStock + delta;
    final updatedMaterial = material.copyWith(
      totalInStock: newStock < 0 ? 0 : newStock,
    );
    _materials[materialId] = updatedMaterial;

    final tx = TransactionModel(
      id: _nextTxId(),
      materialId: materialId,
      type: 'adjustment',
      quantity: delta.abs(),
      teamId: null,
      performedBy: performedBy,
      note: note,
      timestamp: DateTime.now(),
    );
    _transactions.add(tx);
    await _saveAll();
  }

  @override
  Future<List<TransactionModel>> getTransactions({
    String? materialId,
    String? teamId,
  }) async {
    await _ensureInit();
    Iterable<TransactionModel> list = _transactions;
    if (materialId != null)
      list = list.where((t) => t.materialId == materialId);
    if (teamId != null) list = list.where((t) => t.teamId == teamId);
    return list.toList();
  }

  Future<void> _ensureInit() async {
    if (_initialized) return;
    _initFuture ??= _loadAll();
    await _initFuture;
  }

  Future<void> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final matJson = prefs.getString('hf_materials');
    final teamJson = prefs.getString('hf_teams');
    final txJson = prefs.getString('hf_transactions');

    if (matJson != null) {
      final Map<String, dynamic> decoded =
          jsonDecode(matJson) as Map<String, dynamic>;
      decoded.forEach((id, map) {
        _materials[id] = MaterialModel.fromMap(
          id,
          Map<String, dynamic>.from(map as Map),
        );
      });
    }
    if (teamJson != null) {
      final Map<String, dynamic> decoded =
          jsonDecode(teamJson) as Map<String, dynamic>;
      decoded.forEach((id, map) {
        _teams[id] = TeamModel.fromMap(
          id,
          Map<String, dynamic>.from(map as Map),
        );
      });
    }
    if (txJson != null) {
      final List<dynamic> decoded = jsonDecode(txJson) as List<dynamic>;
      _transactions.clear();
      for (final e in decoded) {
        final map = Map<String, dynamic>.from(e as Map);
        _transactions.add(
          TransactionModel.fromMap(map['id'] as String? ?? _nextTxId(), map),
        );
      }
    }

    _initialized = true;
  }

  Future<void> _saveAll() async {
    final prefs = await SharedPreferences.getInstance();
    final mats = _materials.map((k, v) => MapEntry(k, v.toMap()));
    final teams = _teams.map((k, v) => MapEntry(k, v.toMap()));
    final txs = _transactions.map((t) => t.toMap()).toList();
    await prefs.setString('hf_materials', jsonEncode(mats));
    await prefs.setString('hf_teams', jsonEncode(teams));
    await prefs.setString('hf_transactions', jsonEncode(txs));
  }
}
