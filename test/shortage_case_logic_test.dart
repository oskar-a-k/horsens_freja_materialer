import 'package:flutter_test/flutter_test.dart';
import 'package:horsens_freja_materialer_web/services/shortage_case_logic.dart';

void main() {
  group('ShortageCaseLogic.calculatedMissing', () {
    test('returns expected minus actual when actual is lower', () {
      final missing = ShortageCaseLogic.calculatedMissing(
        expected: 20,
        actual: 17,
      );

      expect(missing, 3);
    });

    test('never returns a negative number', () {
      final missing = ShortageCaseLogic.calculatedMissing(
        expected: 8,
        actual: 12,
      );

      expect(missing, 0);
    });
  });

  group('ShortageCaseLogic.groupOpenCases', () {
    test('keeps one active grouped case per team and material', () {
      final grouped = ShortageCaseLogic.groupOpenCases([
        const ShortageCaseRecord(
          docId: 'older',
          teamId: 'u16',
          teamName: 'U16',
          materialId: 'ball',
          materialName: 'Bolde',
          reportedQuantity: 2,
          note: 'Old note',
          source: 'coach_report',
          reportedByEmail: 'coach@club.dk',
          createdAtMillis: 100,
        ),
        const ShortageCaseRecord(
          docId: 'newer',
          teamId: 'u16',
          teamName: 'U16',
          materialId: 'ball',
          materialName: 'Bolde',
          reportedQuantity: 3,
          note: 'Newest note',
          source: 'auto_gap',
          reportedByEmail: 'admin@club.dk',
          createdAtMillis: 200,
        ),
        const ShortageCaseRecord(
          docId: 'other-case',
          teamId: 'u17',
          teamName: 'U17',
          materialId: 'ball',
          materialName: 'Bolde',
          reportedQuantity: 1,
          note: 'Separate team',
          source: 'coach_report',
          reportedByEmail: 'u17@club.dk',
          createdAtMillis: 150,
        ),
      ]);

      expect(grouped.length, 2);

      final u16Ball = grouped[ShortageCaseLogic.caseKey('u16', 'ball')];
      expect(u16Ball, isNotNull);
      expect(u16Ball!.reportedQuantity, 3);
      expect(u16Ball.source, 'auto_gap');
      expect(u16Ball.docIds, ['newer', 'older']);

      final u17Ball = grouped[ShortageCaseLogic.caseKey('u17', 'ball')];
      expect(u17Ball, isNotNull);
      expect(u17Ball!.reportedQuantity, 1);
      expect(u17Ball.docIds, ['other-case']);
    });
  });

  group('ShortageCaseLogic.planUpsert', () {
    test('creates a new case when no open case exists', () {
      final plan = ShortageCaseLogic.planUpsert(const []);

      expect(plan.shouldCreate, isTrue);
      expect(plan.docIdToUpdate, isNull);
    });

    test(
      'updates the newest existing open case instead of creating a duplicate',
      () {
        final plan = ShortageCaseLogic.planUpsert([
          const ShortageCaseRecord(
            docId: 'older',
            teamId: 'u16',
            teamName: 'U16',
            materialId: 'ball',
            materialName: 'Bolde',
            reportedQuantity: 2,
            note: 'Old note',
            source: 'coach_report',
            reportedByEmail: 'coach@club.dk',
            createdAtMillis: 100,
          ),
          const ShortageCaseRecord(
            docId: 'newer',
            teamId: 'u16',
            teamName: 'U16',
            materialId: 'ball',
            materialName: 'Bolde',
            reportedQuantity: 3,
            note: 'New note',
            source: 'auto_gap',
            reportedByEmail: 'admin@club.dk',
            createdAtMillis: 200,
          ),
        ]);

        expect(plan.shouldCreate, isFalse);
        expect(plan.docIdToUpdate, 'newer');
      },
    );
  });

  group('ShortageCaseLogic.isResolvedByStatusCandidate', () {
    test('returns true when current missing is zero', () {
      expect(ShortageCaseLogic.isResolvedByStatusCandidate(0), isTrue);
    });

    test('returns false when current missing is still positive', () {
      expect(ShortageCaseLogic.isResolvedByStatusCandidate(2), isFalse);
    });
  });
}
