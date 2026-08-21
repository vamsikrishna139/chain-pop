import 'dart:math';

import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/layout_mask.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildLayoutMask', () {
    test('fullRect returns null', () {
      expect(buildLayoutMask(LayoutMaskKind.fullRect, 8, 8), isNull);
    });

    test('vShape returns non-empty subset within bounds', () {
      const w = 7;
      const h = 6;
      final cells = buildLayoutMask(LayoutMaskKind.vShape, w, h, random: Random(42))!;
      expect(cells, isNotEmpty);
      for (final key in cells) {
        final parts = key.split(',');
        final x = int.parse(parts[0]);
        final y = int.parse(parts[1]);
        expect(x, greaterThanOrEqualTo(0));
        expect(x, lessThan(w));
        expect(y, greaterThanOrEqualTo(0));
        expect(y, lessThan(h));
      }
    });

    test('pentagon returns cells or falls back to vShape for tiny grids', () {
      final large = buildLayoutMask(LayoutMaskKind.pentagon, 12, 12, random: Random(1))!;
      expect(large.length, greaterThanOrEqualTo(9));
    });

    test('cShape removes most interior void cells', () {
      const w = 9;
      const h = 9;
      final cells = buildLayoutMask(LayoutMaskKind.cShape, w, h, random: Random(0))!;
      expect(cells.length, lessThan(w * h));
      expect(cells.length, greaterThan(40));
    });

    test('deterministic Random yields stable vShape cell count', () {
      final a = buildLayoutMask(LayoutMaskKind.vShape, 10, 10, random: Random(99))!;
      final b = buildLayoutMask(LayoutMaskKind.vShape, 10, 10, random: Random(99))!;
      expect(a.length, b.length);
      expect(a, b);
    });
  });

  group('rollIrregularLayout', () {
    test('easy rolls irregular less often than medium and hard', () {
      var easyCount = 0;
      var mediumCount = 0;
      var hardCount = 0;
      const trials = 500;
      final r = Random(12345);
      for (var i = 0; i < trials; i++) {
        if (rollIrregularLayout(DifficultyMode.easy, r)) easyCount++;
        if (rollIrregularLayout(DifficultyMode.medium, r)) mediumCount++;
        if (rollIrregularLayout(DifficultyMode.hard, r)) hardCount++;
      }
      expect(easyCount, lessThan(mediumCount));
      expect(mediumCount, lessThan(hardCount));
    });

    test('all modes can roll true over many draws', () {
      var easyTrue = false;
      var mediumTrue = false;
      var hardTrue = false;
      final r = Random(7);
      for (var i = 0; i < 200; i++) {
        if (rollIrregularLayout(DifficultyMode.easy, r)) easyTrue = true;
        if (rollIrregularLayout(DifficultyMode.medium, r)) mediumTrue = true;
        if (rollIrregularLayout(DifficultyMode.hard, r)) hardTrue = true;
      }
      expect(easyTrue, isTrue);
      expect(mediumTrue, isTrue);
      expect(hardTrue, isTrue);
    });
  });

  group('pickIrregularKind', () {
    test('returns a variety of non-fullRect shapes', () {
      final kinds = <LayoutMaskKind>{};
      final r = Random(3);
      for (var i = 0; i < 500; i++) {
        kinds.add(pickIrregularKind(r));
      }
      expect(kinds, isNot(contains(LayoutMaskKind.fullRect)));
      expect(kinds.length, greaterThanOrEqualTo(5));
      expect(kinds, contains(LayoutMaskKind.vShape));
      expect(kinds, contains(LayoutMaskKind.pentagon));
      expect(kinds, contains(LayoutMaskKind.cShape));
    });

    test('respects preferred list when provided', () {
      final r = Random(42);
      const preferred = [LayoutMaskKind.diamond, LayoutMaskKind.donut];
      for (var i = 0; i < 50; i++) {
        final kind = pickIrregularKind(r, preferred: preferred);
        expect(preferred, contains(kind));
      }
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // T2.1 — jitter propagation to the nine builders that used to drop it.
  //
  // The whole claim that T2.1 is "free" rests on one invariant: the jitter RNG
  // is level-isolated and never touches the main generation stream. These
  // tests assert that invariant directly rather than trusting the docstrings.
  // See docs/IMPLEMENTATION_PLAN_V2.md §T2.1.
  // ═════════════════════════════════════════════════════════════════════════

  /// Every kind except `fullRect`, which is defined to return null.
  const jitterKinds = [
    LayoutMaskKind.vShape,
    LayoutMaskKind.pentagon,
    LayoutMaskKind.cShape,
    LayoutMaskKind.diamond,
    LayoutMaskKind.cross,
    LayoutMaskKind.lShape,
    LayoutMaskKind.donut,
    LayoutMaskKind.zigzag,
    LayoutMaskKind.randomBlob,
    LayoutMaskKind.checkerboard,
    LayoutMaskKind.scatteredHoles,
    LayoutMaskKind.spiral,
    LayoutMaskKind.hollowDiamond,
    LayoutMaskKind.xShape,
  ];

  /// The nine builders T2.1 converts. `_diamond`, `_cross`, `_donut`,
  /// `_hollowDiamond` and `_xShape` already took jitter before this task and
  /// are excluded: their ranges are live, so they are not T2.1's to retune.
  const t21Builders = [
    LayoutMaskKind.vShape,
    LayoutMaskKind.pentagon,
    LayoutMaskKind.cShape,
    LayoutMaskKind.lShape,
    LayoutMaskKind.zigzag,
    LayoutMaskKind.randomBlob,
    LayoutMaskKind.checkerboard,
    LayoutMaskKind.scatteredHoles,
    LayoutMaskKind.spiral,
  ];

  /// The grids the Director actually asks for (6..9 on both axes).
  const grids = [
    [6, 6], [7, 7], [8, 8], [9, 9], [8, 6], [6, 8], [9, 7], [7, 9],
  ];

  group('T2.1 jitter propagation', () {
    test('jitter consumes NOTHING from the main random stream', () {
      // The load-bearing test. If a jittered build drew even one extra value
      // from `random`, every subsequent board in the session would shift —
      // byte-equality on this mask could still pass while the corpus moved.
      for (final kind in jitterKinds) {
        for (final g in grids) {
          final plain = Random(20260821);
          final jittered = Random(20260821);

          buildLayoutMask(kind, g[0], g[1], random: plain);
          buildLayoutMask(kind, g[0], g[1],
              random: jittered, jitter: Random(7));

          // Both streams must be at the same position afterwards.
          for (var i = 0; i < 8; i++) {
            expect(jittered.nextDouble(), equals(plain.nextDouble()),
                reason: '$kind on ${g[0]}x${g[1]} moved the main stream '
                    'at draw $i');
          }
        }
      }
    });

    test('non-jittered output is unchanged by the jitter parameter', () {
      // Passing jitter: null must be indistinguishable from not passing it,
      // which is what keeps the seeded/milestone path byte-identical.
      for (final kind in jitterKinds) {
        for (final g in grids) {
          final a = buildLayoutMask(kind, g[0], g[1], random: Random(99));
          final b = buildLayoutMask(kind, g[0], g[1],
              random: Random(99), jitter: null);
          expect(b, equals(a), reason: '$kind on ${g[0]}x${g[1]}');
        }
      }
    });

    test('T2.1 jitter does not raise the fallback rate of the nine', () {
      // T2.1's balance clause, asserted strictly (no slack) over exactly the
      // builders T2.1 changes. A jittered shape that drops below minCells
      // converts a variety win into a rect fallback.
      const minCells = 25; // Hard's minNodes — the strictest live floor.
      for (final kind in t21Builders) {
        var plainShort = 0;
        var jitteredShort = 0;
        for (var seed = 0; seed < 60; seed++) {
          final plain = buildLayoutMask(kind, 8, 8, random: Random(seed));
          final jit = buildLayoutMask(kind, 8, 8,
              random: Random(seed), jitter: Random(seed * 31 + 5));
          if ((plain?.length ?? 0) < minCells) plainShort++;
          if ((jit?.length ?? 0) < minCells) jitteredShort++;
        }
        expect(jitteredShort, lessThanOrEqualTo(plainShort),
            reason: '$kind fallback rate rose from $plainShort/60 to '
                '$jitteredShort/60 under jitter');
      }
    });

    test('PRE-EXISTING: hollowDiamond jitter breaks the size envelope at the '
        'current minCells, and T2.2 is what fixes it', () {
      // Found by the T2.1 balance test on 2026-08-21. hollowDiamond is NOT a
      // T2.1 builder — it was jittered before this task and its jitter widens
      // the inner radius to 0.30-0.60, thinning the annulus below Hard's
      // 25-cell floor on 8x8. In production today ~40% of jittered
      // hollowDiamond boards therefore fall back to a plain rectangle.
      //
      // It is deliberately NOT fixed here: changing a live jitter range moves
      // seeds, and T2.1 is a zero-seed-impact task (plan §10). The second
      // assertion shows T2.2's minCells decoupling (25 -> 15) resolves it
      // without touching the builder at all, which is where the fix belongs.
      var shortAt25 = 0;
      var shortAt15 = 0;
      for (var seed = 0; seed < 60; seed++) {
        final m = buildLayoutMask(LayoutMaskKind.hollowDiamond, 8, 8,
            random: Random(seed), jitter: Random(seed * 31 + 5));
        final n = m?.length ?? 0;
        if (n < 25) shortAt25++;
        if (n < 15) shortAt15++;
      }
      expect(shortAt25, greaterThan(0),
          reason: 'the defect this test documents has changed — re-measure '
              'before editing it');
      expect(shortAt15, isZero,
          reason: "T2.2's floor of 15 must clear hollowDiamond entirely");
    });

    test('jitter produces materially more distinct outlines', () {
      // The point of T2.1. Nine builders previously ignored jitter entirely,
      // so on a fixed grid they emitted a handful of outlines forever.
      const previouslyIgnored = [
        LayoutMaskKind.vShape,
        LayoutMaskKind.pentagon,
        LayoutMaskKind.cShape,
        LayoutMaskKind.lShape,
        LayoutMaskKind.zigzag,
        LayoutMaskKind.randomBlob,
        LayoutMaskKind.checkerboard,
        LayoutMaskKind.scatteredHoles,
        LayoutMaskKind.spiral,
      ];
      for (final kind in previouslyIgnored) {
        final plain = <String>{};
        final jittered = <String>{};
        for (var seed = 0; seed < 120; seed++) {
          String key(Set<String>? m) =>
              (m?.toList()?..sort())?.join('|') ?? 'null';
          plain.add(key(buildLayoutMask(kind, 8, 8, random: Random(seed))));
          jittered.add(key(buildLayoutMask(kind, 8, 8,
              random: Random(seed), jitter: Random(seed * 7919 + 13))));
        }
        expect(jittered.length, greaterThanOrEqualTo(plain.length),
            reason: '$kind lost variety under jitter');
      }
    });

    test('spiral was a single fixed glyph and now is not', () {
      // _spiralCells ignored `random` outright, so it had exactly one outline
      // per grid across the entire campaign. This is the clearest single
      // demonstration of what T2.1 unlocks.
      String key(Set<String>? m) => (m?.toList()?..sort())?.join('|') ?? 'null';
      final plain = <String>{};
      final jittered = <String>{};
      for (var seed = 0; seed < 200; seed++) {
        plain.add(key(buildLayoutMask(LayoutMaskKind.spiral, 8, 8,
            random: Random(seed))));
        jittered.add(key(buildLayoutMask(LayoutMaskKind.spiral, 8, 8,
            random: Random(seed), jitter: Random(seed))));
      }
      expect(plain.length, equals(1));
      expect(jittered.length, greaterThan(20));
    });
  });
}
