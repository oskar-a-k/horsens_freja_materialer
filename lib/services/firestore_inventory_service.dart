import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/material_model.dart';
import '../models/team_model.dart';
import '../models/transaction_model.dart';
import 'inventory_service.dart';

class FirestoreInventoryService implements InventoryService {
  final FirebaseFirestore firestore;

  FirestoreInventoryService({required this.firestore});

  CollectionReference<Map<String, dynamic>> get _materialsRef =>
      firestore.collection('materials');
  CollectionReference<Map<String, dynamic>> get _teamsRef =>
      firestore.collection('teams');
  CollectionReference<Map<String, dynamic>> get _transactionsRef =>
      firestore.collection('transactions');

  @override
  Future<MaterialModel> createMaterial(MaterialModel material) async {
    await _materialsRef.doc(material.id).set(material.toMap());
    return material;
  }

  @override
  Future<void> updateMaterial(MaterialModel material) async {
    await _materialsRef.doc(material.id).update(material.toMap());
  }

  @override
  Future<void> deleteMaterial(String materialId) async {
    await _materialsRef.doc(materialId).delete();
  }

  @override
  Future<List<MaterialModel>> listMaterials() async {
    final snapshot = await _materialsRef.get();
    return snapshot.docs
        .map((doc) => MaterialModel.fromMap(doc.id, doc.data()))
        .toList();
  }

  @override
  Future<TeamModel> createTeam(TeamModel team) async {
    await _teamsRef.doc(team.id).set(team.toMap());
    return team;
  }

  @override
  Future<void> updateTeam(TeamModel team) async {
    await _teamsRef.doc(team.id).update(team.toMap());
  }

  @override
  Future<void> deleteTeam(String teamId) async {
    await _teamsRef.doc(teamId).delete();
  }

  @override
  Future<List<TeamModel>> listTeams() async {
    final snapshot = await _teamsRef.get();
    return snapshot.docs
        .map((doc) => TeamModel.fromMap(doc.id, doc.data()))
        .toList();
  }

  @override
  Future<void> assignToTeam(
    String materialId,
    String teamId,
    int quantity,
    String performedBy, {
    String? note,
  }) async {
    final materialDoc = _materialsRef.doc(materialId);
    final teamDoc = _teamsRef.doc(teamId);

    await firestore.runTransaction((transaction) async {
      final materialSnapshot = await transaction.get(materialDoc);
      final teamSnapshot = await transaction.get(teamDoc);

      if (!materialSnapshot.exists) throw StateError('Material not found');
      if (!teamSnapshot.exists) throw StateError('Team not found');

      final material = MaterialModel.fromMap(
        materialSnapshot.id,
        materialSnapshot.data()!,
      );
      final team = TeamModel.fromMap(teamSnapshot.id, teamSnapshot.data()!);

      transaction.update(materialDoc, {
        'totalInStock': material.totalInStock - quantity,
        'updatedAt': DateTime.now().toIso8601String(),
      });

      final newHoldings = Map<String, int>.from(team.holdings);
      newHoldings[materialId] = (newHoldings[materialId] ?? 0) + quantity;
      transaction.update(teamDoc, {
        'holdings': newHoldings,
        'updatedAt': DateTime.now().toIso8601String(),
      });

      final tx = TransactionModel(
        id: _transactionsRef.doc().id,
        materialId: materialId,
        type: 'assign_to_team',
        quantity: quantity,
        teamId: teamId,
        performedBy: performedBy,
        note: note,
        timestamp: DateTime.now(),
      );
      transaction.set(_transactionsRef.doc(tx.id), tx.toMap());
    });
  }

  @override
  Future<void> returnFromTeam(
    String materialId,
    String teamId,
    int quantity,
    String performedBy, {
    String? note,
  }) async {
    final materialDoc = _materialsRef.doc(materialId);
    final teamDoc = _teamsRef.doc(teamId);

    await firestore.runTransaction((transaction) async {
      final materialSnapshot = await transaction.get(materialDoc);
      final teamSnapshot = await transaction.get(teamDoc);

      if (!materialSnapshot.exists) throw StateError('Material not found');
      if (!teamSnapshot.exists) throw StateError('Team not found');

      final material = MaterialModel.fromMap(
        materialSnapshot.id,
        materialSnapshot.data()!,
      );
      final team = TeamModel.fromMap(teamSnapshot.id, teamSnapshot.data()!);

      final currentHeld = team.holdings[materialId] ?? 0;
      final toReturn = quantity > currentHeld ? currentHeld : quantity;

      transaction.update(materialDoc, {
        'totalInStock': material.totalInStock + toReturn,
        'updatedAt': DateTime.now().toIso8601String(),
      });

      final newHoldings = Map<String, int>.from(team.holdings);
      final remaining = (newHoldings[materialId] ?? 0) - toReturn;
      final newExpected = Map<String, int>.from(team.expectedHoldings);
      if (remaining <= 0) {
        newHoldings.remove(materialId);
        newExpected.remove(materialId);
      } else {
        newHoldings[materialId] = remaining;
      }
      transaction.update(teamDoc, {
        'holdings': newHoldings,
        'expectedHoldings': newExpected,
        'updatedAt': DateTime.now().toIso8601String(),
      });

      final tx = TransactionModel(
        id: _transactionsRef.doc().id,
        materialId: materialId,
        type: 'return_from_team',
        quantity: toReturn,
        teamId: teamId,
        performedBy: performedBy,
        note: note,
        timestamp: DateTime.now(),
      );
      transaction.set(_transactionsRef.doc(tx.id), tx.toMap());
    });
  }

  @override
  Future<void> adjustStock(
    String materialId,
    int delta,
    String performedBy, {
    String? note,
  }) async {
    final materialDoc = _materialsRef.doc(materialId);
    await firestore.runTransaction((transaction) async {
      final materialSnapshot = await transaction.get(materialDoc);
      if (!materialSnapshot.exists) throw StateError('Material not found');
      final material = MaterialModel.fromMap(
        materialSnapshot.id,
        materialSnapshot.data()!,
      );
      final newStock = material.totalInStock + delta;
      transaction.update(materialDoc, {
        'totalInStock': newStock < 0 ? 0 : newStock,
        'updatedAt': DateTime.now().toIso8601String(),
      });

      final tx = TransactionModel(
        id: _transactionsRef.doc().id,
        materialId: materialId,
        type: 'adjustment',
        quantity: delta.abs(),
        teamId: null,
        performedBy: performedBy,
        note: note,
        timestamp: DateTime.now(),
      );
      transaction.set(_transactionsRef.doc(tx.id), tx.toMap());
    });
  }

  @override
  Future<List<TransactionModel>> getTransactions({
    String? materialId,
    String? teamId,
  }) async {
    Query<Map<String, dynamic>> query = _transactionsRef;
    if (materialId != null) {
      query = query.where('materialId', isEqualTo: materialId);
    }
    if (teamId != null) query = query.where('teamId', isEqualTo: teamId);
    final snapshot = await query.get();
    return snapshot.docs
        .map((doc) => TransactionModel.fromMap(doc.id, doc.data()))
        .toList();
  }
}
