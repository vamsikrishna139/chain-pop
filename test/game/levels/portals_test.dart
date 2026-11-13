// W2.7 — portal pipeline fixes (audit P1-6 a, b, d) and the rollout switch.
library;

import 'package:chain_pop/game/levels/generation/generation.dart';
import 'package:chain_pop/game/levels/generation/level_enrichment.dart';
import 'package:chain_pop/game/levels/generation/progression_profile.dart';
import 'package:chain_pop/game/levels/grid_cell_key.dart';
import 'package:chain_pop/game/levels/level.dart';
import 'package:chain_pop/game/levels/level_solver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => PortalRollout.enabled = false);

  test('gridCellX / gridCellY invert gridCellKey on every cell', () {
    for (var y = 0; y < 20; y++) {
      for (var x = 0; x < 20; x++) {
        final k = gridCellKey(x, y);
        expect((gridCellX(k), gridCellY(k)), (x, y));
      }
    }
    // The audit's example: the old base-1000 decode turned (3,4) into
    // (147, 262), far off any board.
    final k = gridCellKey(3, 4);
    expect(k, 262147);
    expect((gridCellX(k), gridCellY(k)), (3, 4));
  });

  test('a portal ray continues from the partner cell', () {
    // (0,1) -> right -> enters portal (1,1), leaves at (3,3), next cell (4,3).
    const portals = [PortalPair(1, 1, 3, 3)];
    final table = SightlineTable.forGrid(5, 5, portals: portals);
    expect(table.hasClearRay(0, 1, Direction.right, {}), isTrue);
    expect(table.hasClearRay(0, 1, Direction.right, {gridCellKey(4, 3)}),
        isFalse,
        reason: 'the cell after the exit portal blocks the ray');
    expect(table.hasClearRay(0, 1, Direction.right, {gridCellKey(2, 1)}),
        isTrue,
        reason: 'the cell after the entry portal is skipped by the warp');
  });

  test('a portal loop is blocked in both the table and the solver', () {
    // Node at (1,1) facing right: (2,1), enter (3,1), exit at (0,1) behind
    // the node, continue right through its own (vacated) cell into (2,1) and
    // (3,1) again — forever.
    const portals = [PortalPair(3, 1, 0, 1)];
    final table = SightlineTable.forGrid(5, 3, portals: portals);
    expect(table.hasClearRay(1, 1, Direction.right, {}), isFalse);

    final node = NodeData(id: 0, x: 1, y: 1, dir: Direction.right);
    final level = LevelData(
      levelId: 0,
      gridWidth: 5,
      gridHeight: 3,
      nodes: [node],
      portalPairs: portals,
    );
    expect(LevelSolver.canRemove(node, level.nodes, level), isFalse,
        reason: 'table and solver must agree, or the constructor would '
            'build boards the solver calls unsolvable');
  });

  test('LevelData.copyWith keeps portals and silhouette', () {
    final l = LevelData(
      levelId: 1,
      gridWidth: 4,
      gridHeight: 4,
      nodes: [NodeData(id: 0, x: 0, y: 0, dir: Direction.up)],
      portalPairs: const [PortalPair(1, 1, 2, 2)],
      silhouetteId: SilhouetteId.values.first,
    );
    final c = l.copyWith(nodes: const []);
    expect(c.portalPairs, same(l.portalPairs));
    expect(c.silhouetteId, l.silhouetteId);
  });

  group('rollout switch', () {
    LevelData hard(int id) =>
        LevelGenerator.neutral().generate(id, mode: DifficultyMode.hard).value;

    test('off: no shipped board has portals', () {
      for (final id in [650, 700, 800, 950]) {
        expect(hard(id).portalPairs, isEmpty, reason: 'L$id');
      }
    });

    test('on: portals ship, sit on empty play cells, and boards solve', () {
      PortalRollout.enabled = true;
      var withPortals = 0;
      for (var id = 626; id <= 676; id++) {
        final l = hard(id);
        expect(LevelSolver.isSolvable(l), isTrue, reason: 'L$id');
        if (l.portalPairs.isEmpty) continue;
        withPortals++;
        final occupied = {for (final n in l.nodes) '${n.x},${n.y}'};
        for (final p in l.portalPairs) {
          for (final cell in [p.cell1, p.cell2]) {
            expect(occupied, isNot(contains(cell)),
                reason: 'L$id: a node sits on portal $cell');
            if (l.playCells != null) {
              expect(l.playCells, contains(cell), reason: 'L$id');
            }
          }
        }
      }
      expect(withPortals, greaterThan(25),
          reason: 'portals are budgeted from sector 6; expected most of '
              'Hard L626-676 to carry one');
    });

    test('on: enrichLevel no longer drops portals', () {
      PortalRollout.enabled = true;
      final config =
          LevelConfiguration.fromLevelId(700, mode: DifficultyMode.hard);
      final raw = LevelData(
        levelId: 700,
        gridWidth: 6,
        gridHeight: 6,
        nodes: [NodeData(id: 0, x: 0, y: 0, dir: Direction.up)],
        portalPairs: const [PortalPair(2, 2, 4, 4)],
      );
      final enriched = enrichLevel(raw, config, DifficultyTier.hard);
      expect(enriched.portalPairs, hasLength(1));
    });
  });
}
