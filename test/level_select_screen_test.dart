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

  group('buildNavGroups — dynamic telescoping', () {
    test('small progress gives individual pills (≤ 7)', () {
      final groups = buildNavGroups(1);
      expect(groups.length, 1);
      expect(groups.first.label, '1–20');
      expect(groups.first.pageCount, 1);
      expect(groups.first.isDrillable, false);
    });

    test('100 unlocked gives 6 individual pills, none drillable', () {
      final groups = buildNavGroups(100);
      expect(groups.length, 6);
      expect(groups.first.label, '1–20');
      for (final g in groups) {
        expect(g.pageCount, 1);
        expect(g.isDrillable, false);
      }
    });

    test('200 unlocked uses 100-level groups, not drillable', () {
      final groups = buildNavGroups(200);
      expect(groups.length, lessThanOrEqualTo(10));

      final bigGroups = groups.where((g) => g.pageCount > 1).toList();
      expect(bigGroups, isNotEmpty);
      expect(bigGroups.first.label, '1–100');
      for (final g in bigGroups) {
        expect(g.isDrillable, false,
            reason: '100-level groups (5 pages) are not drillable');
      }
    });

    test('500 unlocked stays under 10 pills, none drillable', () {
      final groups = buildNavGroups(500);
      expect(groups.length, lessThanOrEqualTo(10));

      for (final g in groups) {
        expect(g.isDrillable, false,
            reason: 'at 500 levels groups are ≤ 100 lvls');
      }
    });

    test('600 unlocked creates drillable 500-level groups', () {
      final groups = buildNavGroups(600);
      expect(groups.length, lessThanOrEqualTo(10));

      final drillable = groups.where((g) => g.isDrillable).toList();
      expect(drillable, isNotEmpty,
          reason: '500-level groups should appear once old pages > 25');
      expect(drillable.first.label, '1–500');
    });

    test('1000 unlocked has drillable groups and ≤ 10 pills', () {
      final groups = buildNavGroups(1000);
      expect(groups.length, lessThanOrEqualTo(10));

      final drillable = groups.where((g) => g.isDrillable).toList();
      expect(drillable.length, greaterThanOrEqualTo(1));

      final recent = groups.where((g) => g.pageCount == 1).toList();
      expect(recent.length, 5);
    });

    test('2000 unlocked stays under 10 pills', () {
      final groups = buildNavGroups(2000);
      expect(groups.length, lessThanOrEqualTo(10));
    });

    test('all pages are covered without gaps or overlaps', () {
      for (final h in [1, 50, 100, 200, 500, 600, 1000, 2000]) {
        final groups = buildNavGroups(h);
        final visible = visibleLevelCardCount(h);
        final totalPages = (visible / 20).ceil();

        expect(groups.first.firstPage, 0,
            reason: 'h=$h: first group must start at page 0');
        expect(groups.last.lastPage, totalPages - 1,
            reason: 'h=$h: last group must end at final page');

        for (int i = 1; i < groups.length; i++) {
          expect(groups[i].firstPage, groups[i - 1].lastPage + 1,
              reason: 'h=$h: group $i must follow group ${i - 1}');
        }
      }
    });
  });

  group('buildSubGroups — drill-down into 100-level sub-groups', () {
    test('a 500-level drillable group splits into 5 sub-groups of 100', () {
      final groups = buildNavGroups(600);
      final drillable = groups.firstWhere((g) => g.isDrillable);
      expect(drillable.label, '1–500');

      final subs = buildSubGroups(drillable, 600);
      expect(subs.length, 5);
      expect(subs[0].label, '1–100');
      expect(subs[1].label, '101–200');
      expect(subs[2].label, '201–300');
      expect(subs[3].label, '301–400');
      expect(subs[4].label, '401–500');

      for (final s in subs) {
        expect(s.isDrillable, false);
        expect(s.pageCount, 5);
      }
    });

    test('sub-groups cover exactly the parent range', () {
      for (final h in [600, 1000, 2000]) {
        final groups = buildNavGroups(h);
        for (final parent in groups.where((g) => g.isDrillable)) {
          final subs = buildSubGroups(parent, h);

          expect(subs.first.firstPage, parent.firstPage,
              reason: 'h=$h ${parent.label}: sub start must match parent');
          expect(subs.last.lastPage, parent.lastPage,
              reason: 'h=$h ${parent.label}: sub end must match parent');

          for (int i = 1; i < subs.length; i++) {
            expect(subs[i].firstPage, subs[i - 1].lastPage + 1,
                reason:
                    'h=$h ${parent.label}: sub $i must follow sub ${i - 1}');
          }
        }
      }
    });

    test('sub-groups of a partial group (< 500 levels) are contiguous', () {
      final groups = buildNavGroups(700);
      final drillable = groups.where((g) => g.isDrillable).toList();

      for (final parent in drillable) {
        final subs = buildSubGroups(parent, 700);
        expect(subs, isNotEmpty);
        expect(subs.first.firstPage, parent.firstPage);
        expect(subs.last.lastPage, parent.lastPage);
      }
    });
  });
}
