import 'package:cloud_firestore/cloud_firestore.dart';

import 'shortage_case_logic.dart';

class ShortageCaseService {
  final FirebaseFirestore firestore;

  ShortageCaseService({required this.firestore});

  CollectionReference<Map<String, dynamic>> get _shortagesRef =>
      firestore.collection('bag_shortages');

  static String keyFor(String teamId, String materialId) {
    return ShortageCaseLogic.caseKey(teamId, materialId);
  }

  static String activeDocumentId(String teamId, String materialId) {
    return ShortageCaseLogic.activeDocumentId(teamId, materialId);
  }

  Future<void> upsertOpenCase({
    required String teamId,
    required String teamName,
    required String materialId,
    required String materialName,
    required int reportedQuantity,
    required String note,
    required String source,
    String? reportedByUid,
    String? reportedByEmail,
  }) async {
    final docId = activeDocumentId(teamId, materialId);
    final docRef = _shortagesRef.doc(docId);

    final payload = {
      'teamId': teamId,
      'teamName': teamName,
      'materialId': materialId,
      'materialName': materialName,
      'quantity': reportedQuantity,
      'reportedQuantity': reportedQuantity,
      'note': note,
      'source': source,
      'reportedByUid': reportedByUid,
      'reportedByEmail': reportedByEmail,
      'updatedAt': FieldValue.serverTimestamp(),
      'caseKey': keyFor(teamId, materialId),
    };

    await firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      if (snapshot.exists) {
        transaction.set(docRef, {
          ...payload,
          'status': 'open',
        }, SetOptions(merge: true));
        return;
      }

      transaction.set(docRef, {
        ...payload,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'open',
      });
    });
  }

  Future<void> closeCases({
    required Iterable<String> docIds,
    required Map<String, dynamic> resolutionFields,
  }) async {
    final uniqueDocIds = docIds.toSet();
    final batch = firestore.batch();
    for (final docId in uniqueDocIds) {
      final sourceRef = _shortagesRef.doc(docId);
      final snapshot = await sourceRef.get();
      if (!snapshot.exists) continue;

      final archiveRef = _shortagesRef.doc();
      batch.set(archiveRef, {
        ...snapshot.data()!,
        ...resolutionFields,
        'archivedFromDocId': docId,
      });
      batch.delete(sourceRef);
    }
    await batch.commit();
  }
}
