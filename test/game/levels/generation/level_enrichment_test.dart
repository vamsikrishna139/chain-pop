import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/difficulty_parameters.dart';
import 'package:chain_pop/game/levels/generation/difficulty_profile.dart';
import 'package:chain_pop/game/levels/generation/level_configuration.dart';
import 'package:chain_pop/game/levels/generation/level_enrichment.dart';
import 'package:chain_pop/game/levels/generation/level_validator.dart';
import 'package:chain_pop/game/levels/level.dart';
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

void main() {
  group('enrichLevel relay placement', () {
    test('relay avoids core rows and enriched level stays solvable', () {
      // Column of left-pointing nodes: every node can always exit, so the
      // base level is ID-order solvable in any state.
      final level = LevelData(
        levelId: 58,
        gridWidth: 6,
        gridHeight: 6,
        nodes: [
          for (var i = 0; i < 6; i++)
            NodeData(id: i, x: 0, y: i, dir: Direction.left),
        ],
      );

      final enriched = enrichLevel(level, _hardConfig(58), DifficultyTier.hard);

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
        levelId: 58,
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

      final enriched = enrichLevel(level, _hardConfig(58), DifficultyTier.hard);

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
      // popping it would rotate row 2 and spin node 3 (←) into ↑, where it
      // rays straight into core 4 at (4,1) — stranding it. Nodes 1 and 3 are
      // safe relay picks (their rotations touch no later node).
      final level = LevelData(
        levelId: 58,
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

      final enriched = enrichLevel(level, _hardConfig(58), DifficultyTier.hard);

      final relays =
          enriched.nodes.where((n) => n.kind == NodeKind.relay).toList();
      expect(relays, hasLength(1));
      expect(relays.single.id, isNot(2),
          reason: 'node 2 rotating row 2 would block node 3 behind core 4');
      expect(LevelValidator().validate(enriched).isValid, isTrue);
    });
  });
}
