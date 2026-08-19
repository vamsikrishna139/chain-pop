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

// ⚠️ BOTH TESTS IN THIS FILE ARE TAGGED `slow` AND DO NOT CURRENTLY TERMINATE.
//
// They guard the solvability invariant (no reachable state is a dead end),
// which is load-bearing — do not delete them. But as written they cannot run:
// `_hasSoftlock` is an exhaustive search over reachable states, and the state
// space is ~5^n (every subset of remaining nodes x every direction combo,
// because a relay rotates an entire row). Measured cost is ~13s per board;
// the file asks for 1300 seeds, i.e. hours.
//
// Sharing the `visited` set (done) cut the search from O(n!) permutations to
// O(states) and was still not enough. A real fix needs a *bound*, e.g.:
//   * cap the exhaustive check to boards of <= 7-8 nodes, or
//   * give the search a visited-state budget and report exhaustion as
//     "inconclusive" rather than "safe" (never as a pass), or
//   * check the invariant against `_relayIsSoftlockSafe` on a small
//     hand-built corpus instead of a generated one.
//
// Until then `--tags slow` will hang on this file too. See the suite-timing
// notes in dart_test.yaml.
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
  }, tags: 'slow');

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
  }, tags: 'slow');
}

/// Exhaustively explores every *reachable state* and returns true if any of
/// them is a softlock (non-empty board with no legal moves).
///
/// [visited] is shared across the whole search on purpose. Whether a state is
/// a dead end depends only on the state, never on the move order that reached
/// it, so each state needs visiting exactly once — and the property under test
/// ("is any reachable state a softlock") is unchanged by sharing it.
///
/// This previously passed `Set<String>.from(visited)` to each recursive call,
/// making memoization per-path rather than global. That degenerates into a
/// walk of every move *permutation*: O(n!) instead of O(states), which on a
/// 10-node board with relay rotations is millions of paths per board across
/// up to 500 boards. It did not merely slow the suite down — it hung it for
/// 30+ minutes. Do not reintroduce the copy.
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
    if (_hasSoftlock(next, visited)) return true;
  }

  return false;
}
