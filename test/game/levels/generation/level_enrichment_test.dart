import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/difficulty_parameters.dart';
import 'package:chain_pop/game/levels/generation/difficulty_profile.dart';
import 'package:chain_pop/game/levels/generation/level_configuration.dart';
import 'package:chain_pop/game/levels/generation/level_enrichment.dart';
import 'package:chain_pop/game/levels/generation/level_validator.dart';
import 'package:chain_pop/game/levels/level.dart';
import 'package:chain_pop/game/levels/level_solver.dart';
import 'package:flutter_test/flutter_test.dart';

LevelConfiguration _hardConfig(int levelId) => LevelConfiguration(
      levelId: levelId,
      gridWidth: 6,
      gridHeight: 6,
      targetNodeCount: 6,
      difficulty: const DifficultyParameters(
        mode: DifficultyMode.hard,
        minChainLength: 2,
        maxChainLength: 6,
        densityFactor: 0.25,
        minNodes: 4,
        maxNodes: 12,
      ),
    );

LevelConfiguration _mediumConfig(int levelId) => LevelConfiguration(
      levelId: levelId,
      gridWidth: 6,
      gridHeight: 6,
      targetNodeCount: 6,
      difficulty: const DifficultyParameters(
        mode: DifficultyMode.medium,
        minChainLength: 2,
        maxChainLength: 6,
        densityFactor: 0.25,
        minNodes: 4,
        maxNodes: 12,
      ),
    );

void main() {
  group('enrichLevel relay placement', () {
    test('relay avoids core rows and enriched level stays solvable', () {
      // Column of left-pointing nodes: every node can always exit, so the
      // base level is ID-order solvable in any state.
      final level = LevelData(
        levelId: 260,
        gridWidth: 6,
        gridHeight: 6,
        nodes: [
          for (var i = 0; i < 6; i++)
            NodeData(id: i, x: 0, y: i, dir: Direction.left),
        ],
      );

      final enriched =
          enrichLevel(level, _hardConfig(260), DifficultyTier.hard);

      final cores = enriched.nodes.where((n) => n.isCore).toList();
      final relays =
          enriched.nodes.where((n) => n.kind == NodeKind.relay).toList();
      expect(cores, hasLength(3));
      expect(relays, hasLength(1));

      final coreRows = cores.map((n) => n.y).toSet();
      expect(coreRows.contains(relays.single.y), isFalse,
          reason: 'a relay sharing a row with a core can rotate the core '
              'into a permanent face-off');

      expect(LevelValidator().validate(enriched).isValid, isTrue);
    });

    test('skips the relay entirely when every candidate sits in a core row',
        () {
      // All six nodes live in rows 0 and 2, and the three cores land across
      // both rows — leaving no row the relay is allowed to occupy.
      final level = LevelData(
        levelId: 261,
        gridWidth: 6,
        gridHeight: 6,
        nodes: [
          NodeData(id: 0, x: 0, y: 0, dir: Direction.left),
          NodeData(id: 1, x: 2, y: 0, dir: Direction.left),
          NodeData(id: 2, x: 0, y: 2, dir: Direction.left),
          NodeData(id: 3, x: 2, y: 2, dir: Direction.left),
          NodeData(id: 4, x: 4, y: 0, dir: Direction.left),
          NodeData(id: 5, x: 4, y: 2, dir: Direction.left),
        ],
      );

      final enriched =
          enrichLevel(level, _hardConfig(261), DifficultyTier.hard);

      final coreRows =
          enriched.nodes.where((n) => n.isCore).map((n) => n.y).toSet();
      final occupiedRows = enriched.nodes.map((n) => n.y).toSet();
      expect(coreRows, occupiedRows,
          reason: 'precondition: cores must cover every occupied row');

      expect(enriched.nodes.where((n) => n.kind == NodeKind.relay), isEmpty);
      expect(LevelValidator().validate(enriched).isValid, isTrue);
    });

    test('rejects relay candidates whose rotation breaks the solution', () {
      // Cores are ids 6/5/4 (rows 5, 3, 1). If node 2 became the relay,
      // popping it in canonical ID order would rotate row 2 and spin node 3
      // (←) into ↑, raying straight into core 4 at (4,1) — invalid for the
      // generator's ID-order validation contract (a player could rescue it by
      // popping core 4 early, but the canonical solution must work as-is).
      // Nodes 1 and 3 are safe picks (their rotations touch no later node).
      final level = LevelData(
        levelId: 262,
        gridWidth: 6,
        gridHeight: 6,
        nodes: [
          NodeData(id: 0, x: 1, y: 4, dir: Direction.left),
          NodeData(id: 1, x: 0, y: 0, dir: Direction.left),
          NodeData(id: 2, x: 0, y: 2, dir: Direction.left),
          NodeData(id: 3, x: 4, y: 2, dir: Direction.left),
          NodeData(id: 4, x: 4, y: 1, dir: Direction.right),
          NodeData(id: 5, x: 5, y: 3, dir: Direction.right),
          NodeData(id: 6, x: 5, y: 5, dir: Direction.right),
        ],
      );

      final enriched =
          enrichLevel(level, _hardConfig(262), DifficultyTier.hard);

      final relays =
          enriched.nodes.where((n) => n.kind == NodeKind.relay).toList();
      expect(relays, hasLength(1));
      expect(relays.single.id, isNot(2),
          reason: 'node 2 rotating row 2 would block node 3 behind core 4');
      expect(LevelValidator().validate(enriched).isValid, isTrue);
    });
  });

  group('enrichLevel core placement', () {
    // Three parallel right-pointing chains on rows 0/2/4 of a 6×5 board. Each
    // chain is a clean linear dependency — the rightmost node (x=5) exits
    // first, x=4 only after it, … x=0 last — so removal waves run 0..5 across
    // the columns and nodes are spread vertically by 2. Ids are assigned in
    // wave order (id 0 = first popped) to mirror the real generator, so the
    // deepest (last-popped) nodes carry the highest ids.
    LevelData chainBoard({int levelId = 10}) {
      final nodes = <NodeData>[];
      var id = 0;
      // wave w corresponds to column x = 5 - w.
      for (var w = 0; w <= 5; w++) {
        final x = 5 - w;
        for (final y in const [0, 2, 4]) {
          nodes.add(NodeData(id: id++, x: x, y: y, dir: Direction.right));
        }
      }
      return LevelData(
        levelId: levelId,
        gridWidth: 6,
        gridHeight: 5,
        nodes: nodes,
      );
    }

    test('cores are guarded, mid-band, and never the deepest nodes', () {
      final level = chainBoard();
      final enriched = enrichLevel(level, _hardConfig(10), DifficultyTier.hard);
      final cores = enriched.nodes.where((n) => n.isCore).toList();
      expect(cores, hasLength(3));

      final waves = LevelSolver.nodeWaveIndices(enriched);
      final maxWave = waves.values.reduce((a, b) => a > b ? a : b);

      for (final c in cores) {
        // Guarded: cannot be popped from the opening state — needs setup.
        expect(LevelSolver.canRemove(c, enriched.nodes, enriched), isFalse,
            reason: 'core ${c.id} should not be immediately extractable');
        // In the climax band [0.35, 0.65].
        final pct = waves[c.id]! / maxWave;
        expect(pct, inInclusiveRange(0.35, 0.65),
            reason: 'core ${c.id} wave percentile $pct out of band');
        // Never the deepest (old behaviour put cores at the very end).
        expect(waves[c.id]!, lessThan(maxWave),
            reason: 'core ${c.id} sits at the deepest wave');
      }

      // Regression lock: the old selector picked the three highest ids; the new
      // one must not.
      final maxId =
          enriched.nodes.map((n) => n.id).reduce((a, b) => a > b ? a : b);
      expect(cores.any((c) => c.id == maxId), isFalse,
          reason: 'the last-popped node must no longer be a core');

      expect(LevelValidator().validate(enriched).isValid, isTrue);
    });

    test('falls back to three cores when the board has no wave depth', () {
      // Every node points left from x=0 ⇒ all exit immediately (wave 0), so the
      // percentile bands are meaningless and the legacy picks must still yield
      // exactly three cores.
      final level = LevelData(
        levelId: 10,
        gridWidth: 6,
        gridHeight: 6,
        nodes: [
          for (var i = 0; i < 6; i++)
            NodeData(id: i, x: 0, y: i, dir: Direction.left),
        ],
      );

      final enriched = enrichLevel(level, _hardConfig(10), DifficultyTier.hard);
      expect(enriched.nodes.where((n) => n.isCore), hasLength(3));
      expect(LevelValidator().validate(enriched).isValid, isTrue);
    });

    test('Medium sector 2 places exactly one core', () {
      final level = chainBoard(levelId: 126);
      final enriched =
          enrichLevel(level, _mediumConfig(126), DifficultyTier.medium);

      expect(enriched.nodes.where((n) => n.isCore), hasLength(1));
      expect(LevelValidator().validate(enriched).isValid, isTrue);
    });

    test('Medium sector 3 places exactly two cores', () {
      final level = chainBoard(levelId: 251);
      final enriched =
          enrichLevel(level, _mediumConfig(251), DifficultyTier.medium);

      expect(enriched.nodes.where((n) => n.isCore), hasLength(2));
      expect(LevelValidator().validate(enriched).isValid, isTrue);
    });
  });
}
