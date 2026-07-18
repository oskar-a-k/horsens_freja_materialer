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
    final snapshot = await _shortagesRef
        .where('teamId', isEqualTo: teamId)
        .where('materialId', isEqualTo: materialId)
        .where('status', isEqualTo: 'open')
        .get();

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
    };

    if (snapshot.docs.isEmpty) {
      final plan = ShortageCaseLogic.planUpsert(const []);
      if (!plan.shouldCreate) return;
      await _shortagesRef.add({
        ...payload,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'open',
      });
      return;
    }

    final plan = ShortageCaseLogic.planUpsert(
      snapshot.docs.map((doc) {
        final data = doc.data();
        final createdAt = data['createdAt'] as Timestamp?;
        return ShortageCaseRecord(
          docId: doc.id,
          teamId: data['teamId'] as String? ?? teamId,
          teamName: data['teamName'] as String? ?? teamName,
          materialId: data['materialId'] as String? ?? materialId,
          materialName: data['materialName'] as String? ?? materialName,
          reportedQuantity:
              (data['reportedQuantity'] as num?)?.toInt() ??
              (data['quantity'] as num?)?.toInt() ??
              0,
          note: (data['note'] as String? ?? '').trim(),
          source: data['source'] as String? ?? source,
          reportedByEmail: data['reportedByEmail'] as String? ?? '',
          createdAtMillis: createdAt?.millisecondsSinceEpoch ?? 0,
        );
      }),
    );

    if (plan.shouldCreate || plan.docIdToUpdate == null) {
      await _shortagesRef.add({
        ...payload,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'open',
      });
      return;
    }

    await _shortagesRef
        .doc(plan.docIdToUpdate)
        .set(payload, SetOptions(merge: true));
  }

  Future<void> closeCases({
    required Iterable<String> docIds,
    required Map<String, dynamic> resolutionFields,
  }) async {
    final batch = firestore.batch();
    for (final docId in docIds.toSet()) {
      batch.update(_shortagesRef.doc(docId), resolutionFields);
    }
    await batch.commit();
  }
}
