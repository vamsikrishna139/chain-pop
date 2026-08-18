import 'package:chain_pop/services/achievements/achievement_catalog.dart';
import 'package:chain_pop/services/achievements/achievement_rules.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the catalog against every constraint Google enforces.
///
/// These are not style checks. Publishing an achievement is irreversible, and a
/// catalog that breaks one of these rules is either rejected at upload or
/// permanently wrong in production — so each one fails the build instead.
void main() {
  group('Play Games hard constraints', () {
    test('total points are exactly the 2,000 budget', () {
      expect(kAchievementTotalPoints, kPlayGamesPointBudget);
    });

    test('every point value is a positive multiple of 5', () {
      for (final a in kAchievementCatalog) {
        expect(a.points, greaterThan(0), reason: a.id);
        expect(a.points % 5, 0, reason: '${a.id} = ${a.points}');
      }
    });

    test('no achievement exceeds the per-entry ceiling', () {
      for (final a in kAchievementCatalog) {
        expect(
          a.points,
          lessThanOrEqualTo(kPlayGamesMaxPointsPerAchievement),
          reason: a.id,
        );
      }
    });

    test('incremental step counts stay inside 2–10,000', () {
      for (final a in kAchievementCatalog) {
        if (a.kind != AchievementKind.incremental) continue;
        expect(a.steps, isNotNull, reason: a.id);
        expect(a.steps!, greaterThanOrEqualTo(kPlayGamesMinSteps), reason: a.id);
        expect(a.steps!, lessThanOrEqualTo(kPlayGamesMaxSteps), reason: a.id);
      }
    });

    test('a target of 1 is standard, never incremental', () {
      // Google's step minimum is 2, so a one-shot condition cannot be modelled
      // as an incremental achievement.
      for (final a in kAchievementCatalog) {
        if (a.target == 1) {
          expect(a.kind, AchievementKind.standard, reason: a.id);
        }
      }
    });

    test('standard entries declare no steps', () {
      for (final a in kAchievementCatalog) {
        if (a.kind == AchievementKind.standard) {
          expect(a.steps, isNull, reason: a.id);
        }
      }
    });

    test('catalog fits inside the 400-achievement lifetime cap', () {
      expect(kAchievementCatalog.length, lessThanOrEqualTo(400));
    });
  });

  group('quality checklist', () {
    test('at least 40 achievements (item 2.7)', () {
      expect(kAchievementCatalog.length, greaterThanOrEqualTo(40));
    });

    test('at least 10 visible achievements (item 2.1)', () {
      final visible = kAchievementCatalog.where((a) => !a.hidden).length;
      expect(visible, greaterThanOrEqualTo(10));
    });

    test('hidden achievements are minimised (item 2.16)', () {
      final hidden = kAchievementCatalog.where((a) => a.hidden).length;
      expect(hidden, lessThanOrEqualTo(2));
    });

    test('names and descriptions are unique and non-empty (item 2.3)', () {
      final names = kAchievementCatalog.map((a) => a.name).toList();
      final descriptions =
          kAchievementCatalog.map((a) => a.description).toList();
      expect(names.toSet().length, names.length, reason: 'duplicate name');
      expect(
        descriptions.toSet().length,
        descriptions.length,
        reason: 'duplicate description',
      );
      for (final a in kAchievementCatalog) {
        expect(a.name.trim(), isNotEmpty, reason: a.id);
        expect(a.description.trim(), isNotEmpty, reason: a.id);
      }
    });

    test('names and descriptions fit Play Console field limits', () {
      for (final a in kAchievementCatalog) {
        expect(a.name.length, lessThanOrEqualTo(100), reason: a.id);
        expect(a.description.length, lessThanOrEqualTo(500), reason: a.id);
      }
    });

    test('four first-hour hooks exist (item 2.2)', () {
      final hooks = kAchievementCatalog
          .where((a) => a.track == AchievementTrack.firstHour)
          .toList();
      expect(hooks.length, greaterThanOrEqualTo(4));
      // None may be hidden — a concealed achievement cannot hook a new player.
      for (final h in hooks) {
        expect(h.hidden, isFalse, reason: h.id);
      }
    });
  });

  group('structure', () {
    test('ids are unique', () {
      final ids = kAchievementCatalog.map((a) => a.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('every catalog entry has a progress rule', () {
      final catalogIds = kAchievementCatalog.map((a) => a.id).toSet();
      final ruleIds = kAchievementRules.keys.toSet();
      expect(
        catalogIds.difference(ruleIds),
        isEmpty,
        reason: 'catalog entries with no rule can never unlock',
      );
      expect(
        ruleIds.difference(catalogIds),
        isEmpty,
        reason: 'rules with no catalog entry are dead code',
      );
    });

    test('lookup map covers the catalog', () {
      expect(kAchievementsById.length, kAchievementCatalog.length);
    });

    test('scale only appears where steps alone cannot reach the target', () {
      for (final a in kAchievementCatalog) {
        if (a.scale > 1) {
          expect(
            a.target,
            greaterThan(kPlayGamesMaxSteps),
            reason: '${a.id} divides progress but does not need to',
          );
        }
      }
    });
  });

  group('AchievementDef.stepsFor', () {
    final lord = kAchievementsById[AchievementIds.nodeLord]!;

    test('divides local progress by scale', () {
      expect(lord.scale, 10);
      expect(lord.stepsFor(10000), 1000);
    });

    test('clamps at the declared step count', () {
      expect(lord.stepsFor(999999), lord.steps);
    });

    test('never reports negative steps', () {
      expect(lord.stepsFor(-5), 0);
    });

    test('reaches full steps exactly at target', () {
      expect(lord.stepsFor(lord.target), lord.steps);
    });
  });
}
