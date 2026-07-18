class CalculatedShortageGap {
  final String teamId;
  final String teamName;
  final String materialId;
  final int expected;
  final int actual;

  const CalculatedShortageGap({
    required this.teamId,
    required this.teamName,
    required this.materialId,
    required this.expected,
    required this.actual,
  });

  int get missing {
    final delta = expected - actual;
    return delta > 0 ? delta : 0;
  }
}

class ShortageCaseRecord {
  final String docId;
  final String teamId;
  final String teamName;
  final String materialId;
  final String materialName;
  final int reportedQuantity;
  final String note;
  final String source;
  final String reportedByEmail;
  final int createdAtMillis;

  const ShortageCaseRecord({
    required this.docId,
    required this.teamId,
    required this.teamName,
    required this.materialId,
    required this.materialName,
    required this.reportedQuantity,
    required this.note,
    required this.source,
    required this.reportedByEmail,
    required this.createdAtMillis,
  });
}

class GroupedShortageCase {
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
  final int createdAtMillis;

  const GroupedShortageCase({
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
    required this.createdAtMillis,
  });
}

class ShortageCaseUpsertPlan {
  final bool shouldCreate;
  final String? docIdToUpdate;

  const ShortageCaseUpsertPlan.create()
    : shouldCreate = true,
      docIdToUpdate = null;

  const ShortageCaseUpsertPlan.update(this.docIdToUpdate)
    : shouldCreate = false;
}

class ShortageCaseLogic {
  static int calculatedMissing({required int expected, required int actual}) {
    final delta = expected - actual;
    return delta > 0 ? delta : 0;
  }

  static String caseKey(String teamId, String materialId) {
    return '$teamId::$materialId';
  }

  static String activeDocumentId(String teamId, String materialId) {
    final safeTeamId = Uri.encodeComponent(teamId);
    final safeMaterialId = Uri.encodeComponent(materialId);
    return 'open__${safeTeamId}__$safeMaterialId';
  }

  static bool isResolvedByStatusCandidate(int currentMissing) {
    return currentMissing <= 0;
  }

  static Map<String, GroupedShortageCase> groupOpenCases(
    Iterable<ShortageCaseRecord> records,
  ) {
    final grouped = <String, List<ShortageCaseRecord>>{};
    for (final record in records) {
      final key = caseKey(record.teamId, record.materialId);
      grouped.putIfAbsent(key, () => []).add(record);
    }

    final result = <String, GroupedShortageCase>{};
    for (final entry in grouped.entries) {
      final sorted = [...entry.value]
        ..sort((a, b) => b.createdAtMillis.compareTo(a.createdAtMillis));
      final primary = sorted.first;
      result[entry.key] = GroupedShortageCase(
        key: entry.key,
        docIds: sorted.map((record) => record.docId).toList(),
        teamId: primary.teamId,
        teamName: primary.teamName,
        materialId: primary.materialId,
        materialName: primary.materialName,
        reportedQuantity: primary.reportedQuantity,
        note: primary.note,
        source: primary.source,
        reportedByEmail: primary.reportedByEmail,
        createdAtMillis: primary.createdAtMillis,
      );
    }
    return result;
  }

  static ShortageCaseUpsertPlan planUpsert(
    Iterable<ShortageCaseRecord> existingOpenCases,
  ) {
    final records = existingOpenCases.toList();
    if (records.isEmpty) {
      return const ShortageCaseUpsertPlan.create();
    }

    final sorted = [...records]
      ..sort((a, b) => b.createdAtMillis.compareTo(a.createdAtMillis));
    return ShortageCaseUpsertPlan.update(sorted.first.docId);
  }
}
