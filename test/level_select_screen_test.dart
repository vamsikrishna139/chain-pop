import 'package:chain_pop/screens/level_select_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('level select count grows beyond 200 when progress exceeds it', () {
    expect(visibleLevelCardCount(1), 20);
    expect(visibleLevelCardCount(18), 20);
    expect(visibleLevelCardCount(19), 20);
    expect(visibleLevelCardCount(20), 21);
    expect(visibleLevelCardCount(200), 201);
    expect(visibleLevelCardCount(205), 206);
  });

  group('buildNavGroups — 100-based summary', () {
    test('small progress still starts with first 20', () {
      final groups = buildNavGroups(1);
      expect(groups.length, 1);
      expect(groups.first.label, '1–20');
      expect(groups.first.pageCount, 1);
      expect(groups.first.isDrillable, true);
    });

    test('100 unlocked shows 1-100 plus remainder', () {
      final groups = buildNavGroups(100);
      expect(groups.length, 2);
      expect(groups[0].label, '1–100');
      expect(groups[1].label, '101');
    });

    test('200 unlocked shows single summary up to 200 plus remainder', () {
      final groups = buildNavGroups(200);
      expect(groups[0].label, '1–200');
      expect(groups[1].label, '201');
    });

    test('700 unlocked shows compact summary and tiny remainder', () {
      final groups = buildNavGroups(700);
      expect(groups[0].label, '1–700');
      expect(groups[1].label, '701');
    });

    test('all levels are covered without gaps or overlaps', () {
      for (final h in [1, 50, 100, 200, 500, 600, 1000, 2000]) {
        final groups = buildNavGroups(h);
        final visible = visibleLevelCardCount(h);

        expect(groups.first.firstLevel, 1,
            reason: 'h=$h: first group must start at level 1');
        expect(groups.last.lastLevel, visible,
            reason: 'h=$h: last group must end at final visible level');

        for (int i = 1; i < groups.length; i++) {
          expect(groups[i].firstLevel, groups[i - 1].lastLevel + 1,
              reason: 'h=$h: group $i must follow group ${i - 1}');
        }
      }
    });
  });

  group('buildSubGroups — 500 -> 100 -> 20 -> individual', () {
    test('1-700 splits to 500 and 200 bands', () {
      const parent = NavGroup('1–700', 1, 700);
      final subs = buildSubGroups(parent, 700);
      expect(subs.map((s) => s.label), ['1–500', '501–700']);
    });

    test('a 200-level band splits to 100-level bands', () {
      const parent = NavGroup('501–700', 501, 700);
      final subs = buildSubGroups(parent, 700);
      expect(subs.map((s) => s.label), ['501–600', '601–700']);
    });

    test('a 100-level band splits to 20-level bands', () {
      const parent = NavGroup('601–700', 601, 700);
      final subs = buildSubGroups(parent, 700);
      expect(subs.length, 5);
      expect(subs.first.label, '601–620');
      expect(subs.last.label, '681–700');
    });

    test('a 20-level band splits to individual levels', () {
      const parent = NavGroup('601–620', 601, 620);
      final subs = buildSubGroups(parent, 700);
      expect(subs.length, 20);
      expect(subs.first.label, '601');
      expect(subs.last.label, '620');
    });

    test('sub-groups always cover parent range contiguously', () {
      for (final parent in const [
        NavGroup('1–700', 1, 700),
        NavGroup('501–700', 501, 700),
        NavGroup('601–700', 601, 700),
        NavGroup('601–620', 601, 620),
      ]) {
        final subs = buildSubGroups(parent, 700);
        expect(subs.first.firstLevel, parent.firstLevel);
        expect(subs.last.lastLevel, parent.lastLevel);
        for (int i = 1; i < subs.length; i++) {
          expect(subs[i].firstLevel, subs[i - 1].lastLevel + 1);
        }
      }
    });
  });
}
