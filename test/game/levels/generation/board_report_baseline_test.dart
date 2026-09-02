// Guards the board-report measurement harness itself (plan P0).
//
// Two things must stay true or the corpus silently lies:
//  1. [FitterVariant.current] reproduces the shipped `BoardLayoutMetrics`
//     fitter exactly, so Experiment A's "what if" columns are anchored to a
//     column that is provably today's behaviour.
//  2. The composition metrics compute what they claim on hand-built boards.

import 'package:chain_pop/game/board_layout.dart';
import 'package:chain_pop/game/levels/level.dart';
import 'package:flutter_test/flutter_test.dart';

import 'board_report_utils.dart';

LevelData _level({
  required int gridW,
  required int gridH,
  required List<(int, int)> cells,
}) =>
    LevelData(
      levelId: 1,
      gridWidth: gridW,
      gridHeight: gridH,
      nodes: [
        for (final (i, c) in cells.indexed)
          NodeData(id: i + 1, x: c.$1, y: c.$2, dir: Direction.up),
      ],
    );

void main() {
  group('FitterVariant mirrors the shipped fitter', () {
    test('matches BoardLayoutMetrics across grids and both devices', () {
      for (final device in ReferenceDevice.all) {
        for (var gw = 4; gw <= 12; gw++) {
          for (var gh = 4; gh <= 12; gh++) {
            for (final (bw, bh) in [(gw, gh), (gw - 1, gh), (3, 3)]) {
              if (bw <= 0 || bh <= 0) continue;
              // The legacy column must still reproduce the single-fill fitter…
              expect(
                fitCellPx(
                  device: device,
                  variant: FitterVariant.current,
                  bboxWidth: bw,
                  bboxHeight: bh,
                  gridWidth: gw,
                  gridHeight: gh,
                ),
                closeTo(
                  BoardLayoutMetrics.fitCellSizeForBoundsCappedToGrid(
                    bandW: device.bandW,
                    bandH: device.bandH,
                    bboxWidth: bw,
                    bboxHeight: bh,
                    gridWidth: gw,
                    gridHeight: gh,
                    targetFill: kLegacyBoardFill,
                  ),
                  1e-9,
                ),
                reason: 'legacy ${device.name} grid ${gw}x$gh bbox ${bw}x$bh',
              );
              // …and the shipped column must reproduce the per-axis default.
              expect(
                fitCellPx(
                  device: device,
                  variant: FitterVariant.perAxis,
                  bboxWidth: bw,
                  bboxHeight: bh,
                  gridWidth: gw,
                  gridHeight: gh,
                ),
                closeTo(
                  BoardLayoutMetrics.fitCellSizeForBoundsCappedToGrid(
                    bandW: device.bandW,
                    bandH: device.bandH,
                    bboxWidth: bw,
                    bboxHeight: bh,
                    gridWidth: gw,
                    gridHeight: gh,
                  ),
                  1e-9,
                ),
                reason: 'shipped ${device.name} grid ${gw}x$gh bbox ${bw}x$bh',
              );
            }
          }
        }
      }
    });

    test('per-axis variant is never smaller than the current one', () {
      for (final device in ReferenceDevice.all) {
        for (var g = 6; g <= 9; g++) {
          final a = fitCellPx(
            device: device,
            variant: FitterVariant.current,
            bboxWidth: g,
            bboxHeight: g,
            gridWidth: g,
            gridHeight: g,
          );
          final b = fitCellPx(
            device: device,
            variant: FitterVariant.perAxis,
            bboxWidth: g,
            bboxHeight: g,
            gridWidth: g,
            gridHeight: g,
          );
          expect(b, greaterThanOrEqualTo(a - 1e-9), reason: '${g}x$g');
        }
      }
    });
  });

  group('CompositionMetrics', () {
    test('empty runs, regions, isolation and local density on a known board',
        () {
      // 6x6 grid; a solid 2x2 block top-left plus one isolated node far away.
      //   . . . . . .
      //   . X X . . .
      //   . X X . . .
      //   . . . . . .
      //   . . . . . X
      //   . . . . . .
      final level = _level(
        gridW: 6,
        gridH: 6,
        cells: [(1, 1), (2, 1), (1, 2), (2, 2), (5, 4)],
      );
      final c = CompositionMetrics.compute(level);

      // Rows 0, 3 are empty (run 1 each); row 5 empty (run 1). Rows 1,2 and 4
      // are occupied, so the longest run of consecutive empty rows is 1.
      expect(c.largestEmptyRowRun, 1);
      // Columns 0, 3, 4 empty → longest consecutive run is cols 3–4 = 2.
      expect(c.largestEmptyColRun, 2);
      // 36 cells − 5 nodes = 31 empty, all 4-connected around the block.
      expect(c.largestEmptyRegion, 31);
      // The lone node at (5,4) has no orthogonal neighbour; block members all do.
      expect(c.isolatedNodeCount, 1);
      // Block members each see 3 of 8 neighbours; the lone node sees 0.
      expect(c.meanLocalDensity, closeTo((4 * 3 / 8 + 0) / 5, 1e-9));
    });

    test('a fully packed grid has no empty structure', () {
      final level = _level(
        gridW: 4,
        gridH: 4,
        cells: [
          for (var y = 0; y < 4; y++)
            for (var x = 0; x < 4; x++) (x, y)
        ],
      );
      final c = CompositionMetrics.compute(level);
      expect(c.largestEmptyRowRun, 0);
      expect(c.largestEmptyColRun, 0);
      expect(c.largestEmptyRegion, 0);
      expect(c.isolatedNodeCount, 0);
    });

    test('an empty level degrades gracefully', () {
      final c =
          CompositionMetrics.compute(_level(gridW: 5, gridH: 5, cells: []));
      expect(c.largestEmptyRegion, 0);
      expect(c.meanLocalDensity, 0);
    });
  });
}
