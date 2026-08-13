import 'package:chain_pop/game/board_layout.dart';
import 'package:chain_pop/game/levels/level.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OccupiedBounds', () {
    test('fromLevel with empty level falls back to full grid', () {
      final level = LevelData(
        levelId: 1,
        gridWidth: 9,
        gridHeight: 9,
        nodes: [],
      );
      final bounds = OccupiedBounds.fromLevel(level, pad: 1);
      expect(bounds.minX, 0);
      expect(bounds.maxX, 8);
      expect(bounds.minY, 0);
      expect(bounds.maxY, 8);
      expect(bounds.bboxWidth, 9);
      expect(bounds.bboxHeight, 9);
    });

    test('fromLevel traces bounds and respects padding', () {
      final level = LevelData(
        levelId: 1,
        gridWidth: 9,
        gridHeight: 9,
        nodes: [
          NodeData(id: 0, x: 2, y: 3, dir: Direction.up),
          NodeData(id: 1, x: 5, y: 6, dir: Direction.down),
        ],
      );
      final bounds = OccupiedBounds.fromLevel(level, pad: 1);
      // Raw minX=2, maxX=5, minY=3, maxY=6
      // Padded: minX=1, maxX=6, minY=2, maxY=7
      expect(bounds.minX, 1);
      expect(bounds.maxX, 6);
      expect(bounds.minY, 2);
      expect(bounds.maxY, 7);
      expect(bounds.bboxWidth, 6);
      expect(bounds.bboxHeight, 6);
    });

    test('fromLevel respects grid boundary clamps', () {
      final level = LevelData(
        levelId: 1,
        gridWidth: 9,
        gridHeight: 9,
        nodes: [
          NodeData(id: 0, x: 0, y: 0, dir: Direction.up),
          NodeData(id: 1, x: 8, y: 8, dir: Direction.down),
        ],
      );
      final bounds = OccupiedBounds.fromLevel(level, pad: 1);
      expect(bounds.minX, 0);
      expect(bounds.maxX, 8);
      expect(bounds.minY, 0);
      expect(bounds.maxY, 8);
    });
  });

  group('BoardLayoutMetrics.fitCellSize', () {
    test('never exceeds band so grid fits (dense grid, narrow band)', () {
      const bandW = 300.0;
      const bandH = 500.0;
      const gw = 18;
      const gh = 18;
      final s = BoardLayoutMetrics.fitCellSize(
        bandW: bandW,
        bandH: bandH,
        gridWidth: gw,
        gridHeight: gh,
      );
      expect(s * gw, lessThanOrEqualTo(bandW + 1e-6));
      expect(s * gh, lessThanOrEqualTo(bandH + 1e-6));
    });

    test('uses minPreferred when it still fits', () {
      final s = BoardLayoutMetrics.fitCellSize(
        bandW: 400,
        bandH: 400,
        gridWidth: 10,
        gridHeight: 10,
      );
      expect(s, greaterThanOrEqualTo(26.0));
      expect(s * 10, lessThanOrEqualTo(400.0 + 1e-6));
    });

    test('compute embeds grid in usable band', () {
      final m = BoardLayoutMetrics.compute(
        screenW: 360,
        screenH: 700,
        topReserved: 100,
        bottomReserved: 70,
        gridWidth: 18,
        gridHeight: 18,
      );
      expect(m.cellSize * 18, lessThanOrEqualTo(m.usableW + 1e-6));
      expect(m.cellSize * 18, lessThanOrEqualTo(m.usableH + 1e-6));
    });
  });

  group('BoardLayoutMetrics.fitCellSizeForBounds', () {
    test('scales correctly according to target fill', () {
      final s = BoardLayoutMetrics.fitCellSizeForBounds(
        bandW: 500,
        bandH: 500,
        bboxWidth: 5,
        bboxHeight: 5,
        targetFill: 0.80,
      );
      // 500 * 0.80 = 400. 400 / 5 = 80
      expect(s, closeTo(80.0, 1e-6));
    });
  });

  group('BoardLayoutMetrics.fitCellSizeForBoundsCappedToGrid', () {
    test('caps so the full grid never overflows the band (sparse board)', () {
      // Tutorial-like: one node in a 4×4 grid → occupied bbox (with pad 1) is
      // 3×3. The raw bounds fit would zoom in until the 4-wide grid spills off.
      const bandW = 288.0; // ≈ 320px small phone minus margins
      const bandH = 600.0;
      final raw = BoardLayoutMetrics.fitCellSizeForBounds(
        bandW: bandW,
        bandH: bandH,
        bboxWidth: 3,
        bboxHeight: 3,
        targetFill: 0.80,
      );
      final capped = BoardLayoutMetrics.fitCellSizeForBoundsCappedToGrid(
        bandW: bandW,
        bandH: bandH,
        bboxWidth: 3,
        bboxHeight: 3,
        gridWidth: 4,
        gridHeight: 4,
        targetFill: 0.80,
      );
      // Raw fit overflows the band when the full 4×4 grid is rendered…
      expect(raw * 4, greaterThan(bandW));
      // …but the capped fit guarantees the full grid fits.
      expect(capped * 4, lessThanOrEqualTo(bandW + 1e-6));
      expect(capped * 4, lessThanOrEqualTo(bandH + 1e-6));
      expect(capped, lessThan(raw));
    });

    test('leaves dense boards untouched (cap does not bind)', () {
      // Fully occupied 6×6: bbox ≈ grid, so the 0.8 target fill already keeps
      // the grid within the band and the cap should not shrink it further.
      const bandW = 500.0;
      const bandH = 500.0;
      final raw = BoardLayoutMetrics.fitCellSizeForBounds(
        bandW: bandW,
        bandH: bandH,
        bboxWidth: 6,
        bboxHeight: 6,
        targetFill: 0.80,
      );
      final capped = BoardLayoutMetrics.fitCellSizeForBoundsCappedToGrid(
        bandW: bandW,
        bandH: bandH,
        bboxWidth: 6,
        bboxHeight: 6,
        gridWidth: 6,
        gridHeight: 6,
        targetFill: 0.80,
      );
      expect(capped, closeTo(raw, 1e-6));
    });
  });

  group('per-axis board fill (P1)', () {
    // Playfield bands the app actually produces, derived from the measured HUD
    // reserves (see test/screens/playfield_insets_reference_test.dart). Small
    // phones use the same formula with their own safe areas.
    const bands = <(String, double, double)>[
      ('320x568', 272.0, 356.0),
      ('360x800', 312.0, 540.0),
      ('390x844', 342.0, 538.0),
      ('430x932', 382.0, 614.0),
    ];

    test('the full grid always fits the band at base zoom', () {
      for (final (label, bandW, bandH) in bands) {
        for (var gw = 4; gw <= 12; gw++) {
          for (var gh = 4; gh <= 12; gh++) {
            // Sweep bboxes from a single-node tutorial board (3×3 after pad)
            // up to the full grid — the sparse end is where the bbox fit
            // would otherwise inflate past the band.
            for (final (bw, bh) in [
              (3, 3),
              (gw ~/ 2 + 1, gh ~/ 2 + 1),
              (gw - 1, gh - 1),
              (gw, gh),
            ]) {
              if (bw <= 0 || bh <= 0) continue;
              final cell = BoardLayoutMetrics.fitCellSizeForBoundsCappedToGrid(
                bandW: bandW,
                bandH: bandH,
                bboxWidth: bw,
                bboxHeight: bh,
                gridWidth: gw,
                gridHeight: gh,
              );
              final why = '$label grid ${gw}x$gh bbox ${bw}x$bh cell $cell';
              expect(cell * gw, lessThanOrEqualTo(bandW + 1e-6), reason: why);
              expect(cell * gh, lessThanOrEqualTo(bandH + 1e-6), reason: why);
              expect(cell, greaterThan(0), reason: why);
            }
          }
        }
      }
    });

    test('never renders smaller than the single-0.80 fill it replaced', () {
      for (final (label, bandW, bandH) in bands) {
        for (var g = 6; g <= 9; g++) {
          final before = BoardLayoutMetrics.fitCellSizeForBoundsCappedToGrid(
            bandW: bandW,
            bandH: bandH,
            bboxWidth: g,
            bboxHeight: g,
            gridWidth: g,
            gridHeight: g,
            targetFill: 0.80,
          );
          final after = BoardLayoutMetrics.fitCellSizeForBoundsCappedToGrid(
            bandW: bandW,
            bandH: bandH,
            bboxWidth: g,
            bboxHeight: g,
            gridWidth: g,
            gridHeight: g,
          );
          expect(after, greaterThanOrEqualTo(before - 1e-9),
              reason: '$label ${g}x$g');
        }
      }
    });

    test('reference arithmetic: 8x8 on 390x844 goes 34.2px -> 40.2px', () {
      const bandW = 342.0;
      const bandH = 538.0;
      final before = BoardLayoutMetrics.fitCellSizeForBoundsCappedToGrid(
        bandW: bandW,
        bandH: bandH,
        bboxWidth: 8,
        bboxHeight: 8,
        gridWidth: 8,
        gridHeight: 8,
        targetFill: 0.80,
      );
      final after = BoardLayoutMetrics.fitCellSizeForBoundsCappedToGrid(
        bandW: bandW,
        bandH: bandH,
        bboxWidth: 8,
        bboxHeight: 8,
        gridWidth: 8,
        gridHeight: 8,
      );
      expect(before, closeTo(34.2, 0.1));
      expect(after, closeTo(40.2, 0.1));
    });

    test('targetFill still overrides both axes for single-fill callers', () {
      final both = BoardLayoutMetrics.fitCellSizeForBounds(
        bandW: 500,
        bandH: 500,
        bboxWidth: 5,
        bboxHeight: 5,
        targetFill: 0.50,
      );
      expect(both, closeTo(50.0, 1e-6));
    });
  });

  group('LevelData.layoutValidationMessage', () {
    test('null when valid', () {
      final level = LevelData(
        levelId: 1,
        gridWidth: 3,
        gridHeight: 3,
        nodes: [
          NodeData(id: 0, x: 0, y: 0, dir: Direction.up),
          NodeData(id: 1, x: 2, y: 2, dir: Direction.down),
        ],
      );
      expect(LevelData.layoutValidationMessage(level), isNull);
    });

    test('detects duplicate cells', () {
      final level = LevelData(
        levelId: 1,
        gridWidth: 3,
        gridHeight: 3,
        nodes: [
          NodeData(id: 0, x: 1, y: 1, dir: Direction.up),
          NodeData(id: 1, x: 1, y: 1, dir: Direction.down),
        ],
      );
      expect(LevelData.layoutValidationMessage(level), isNotNull);
    });

    test('detects out of bounds', () {
      final level = LevelData(
        levelId: 1,
        gridWidth: 3,
        gridHeight: 3,
        nodes: [
          NodeData(id: 0, x: 3, y: 0, dir: Direction.up),
        ],
      );
      expect(LevelData.layoutValidationMessage(level), isNotNull);
    });
  });
}
