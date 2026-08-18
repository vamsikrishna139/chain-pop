import 'package:chain_pop/game/levels/generation/difficulty_parameters.dart';
import 'package:chain_pop/game/levels/generation/difficulty_profile.dart';
import 'package:chain_pop/game/levels/generation/level_configuration.dart';
import 'package:chain_pop/game/levels/generation/level_enrichment.dart';
import 'package:chain_pop/game/levels/generation/level_generator.dart';
import 'package:chain_pop/game/levels/generation/progression_profile.dart';
import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/level.dart';
import 'package:chain_pop/game/levels/level_solver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('One-relay softlock property test', () {
    final generator = LevelGenerator();
    const config = LevelConfiguration(
      levelId: 9999,
      gridWidth: 5,
      gridHeight: 5,
      targetNodeCount: 10,
      difficulty: DifficultyParameters(
        mode: DifficultyMode.hard,
        minChainLength: 2,
        maxChainLength: 10,
        densityFactor: 0.5,
        minNodes: 5,
        maxNodes: 10,
      ),
    );

    int boardsTested = 0;

    for (int seed = 0; seed < 500; seed++) {
      final genResult = generator.generateFromConfiguration(
        config,
        primarySeed: seed,
        applyMilestones: false,
      );

      if (!genResult.isSuccess) continue;

      final enriched = enrichLevel(
        genResult.value,
        config,
        DifficultyTier.hard,
        mechanicOverride: const MechanicBudgetOverride(
          coreCount: 0,
          lockCount: 0,
          relayCount: 1,
          phaseGateCount: 0,
          portalPairCount: 0,
        ),
      );

      final relays =
          enriched.nodes.where((n) => n.kind == NodeKind.relay).toList();
      if (relays.length != 1) continue;

      boardsTested++;

      expect(_hasSoftlock(enriched, {}), isFalse,
          reason:
              'Level $seed softlocked despite passing _relayIsSoftlockSafe');
    }

    // ignore: avoid_print
    print('Tested $boardsTested boards with 1 relay exhaustively.');
    expect(boardsTested, greaterThan(10),
        reason: 'Need to test enough boards to be confident');
  });

  test('Two-relay softlock property test', () {
    final generator = LevelGenerator();
    const config = LevelConfiguration(
      levelId: 9999,
      gridWidth: 6,
      gridHeight: 6,
      targetNodeCount: 10,
      difficulty: DifficultyParameters(
        mode: DifficultyMode.hard,
        minChainLength: 2,
        maxChainLength: 10,
        densityFactor: 0.5,
        minNodes: 6,
        maxNodes: 10,
      ),
    );

    int boardsTested = 0;

    for (int seed = 0; seed < 800; seed++) {
      final genResult = generator.generateFromConfiguration(
        config,
        primarySeed: seed,
        applyMilestones: false,
      );

      if (!genResult.isSuccess) continue;

      final enriched = enrichLevel(
        genResult.value,
        config,
        DifficultyTier.hard,
        mechanicOverride: const MechanicBudgetOverride(
          coreCount: 0,
          lockCount: 0,
          relayCount: 2,
          phaseGateCount: 0,
          portalPairCount: 0,
        ),
      );

      final relays =
          enriched.nodes.where((n) => n.kind == NodeKind.relay).toList();
      if (relays.length != 2) continue; // enrichment rejected one or both

      // Verify relays are in distinct rows
      expect(relays[0].y, isNot(relays[1].y),
          reason: 'Two relays must be in distinct rows');

      boardsTested++;

      expect(_hasSoftlock(enriched, {}), isFalse,
          reason:
              'Level seed=$seed with 2 relays softlocked despite passing _relayIsSoftlockSafe');
    }

    // ignore: avoid_print
    print('Tested $boardsTested boards with 2 relays exhaustively.');
    expect(boardsTested, greaterThan(5),
        reason: 'Need to test enough 2-relay boards');
  });
}

/// Exhaustively explores all legal move orders and returns true if any path
/// leads to a softlock (non-empty board with no legal moves).
bool _hasSoftlock(LevelData current, Set<String> visited) {
  if (current.nodes.isEmpty) return false;

  final stateKey =
      current.nodes.map((n) => '${n.id}:${n.dir.index}').toList()..sort();
  final stateHash = stateKey.join('|');
  if (visited.contains(stateHash)) {
    return false;
  }
  visited.add(stateHash);

  final moves = <int>[];
  for (final n in current.nodes) {
    if (LevelSolver.canRemove(n, current.nodes, current)) {
      moves.add(n.id);
    }
  }

  // No moves left but board is not clear -> SOFTLOCK!
  if (moves.isEmpty) return true;

  for (final moveId in moves) {
    final moveNode = current.nodes.firstWhere((n) => n.id == moveId);
    final nextNodes = current.nodes.where((n) => n.id != moveId).map((n) {
      if (moveNode.kind == NodeKind.relay && n.y == moveNode.y) {
        return n.copyWith(dir: n.dir.rotatedCw);
      }
      return n;
    }).toList();

    final next = LevelData(
      levelId: current.levelId,
      gridWidth: current.gridWidth,
      gridHeight: current.gridHeight,
      playCells: current.playCells,
      nodes: nextNodes,
    );
    if (_hasSoftlock(next, Set<String>.from(visited))) return true;
  }

  return false;
}
