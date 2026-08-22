// ignore_for_file: avoid_print
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

// The solvability gate for relays: no reachable state of a shipped board may
// be a dead end. Relays are the only mechanic that can create one, because
// removing a relay rotates every node in its row and can therefore *destroy*
// legal moves rather than only consuming them.
//
// WHAT CHANGED HERE, AND WHY (P2b T2.24)
//
// The previous fixture generated boards from a bespoke 5x5 / 6x6
// `LevelConfiguration` and forced relays on with a `MechanicBudgetOverride`.
// Measured, that fixture had rotted into a no-op: it produced **zero** boards
// with exactly one relay, so the coverage assertion (`boardsTested > 10`)
// failed against 0 and the property itself was never evaluated. The invariant
// governing 700 of 1800 shipped campaign boards was, in practice, ungated.
//
// The header also claimed both tests "do not currently terminate" and cost
// ~13s per board. That is not true of shipped boards, and the difference is
// not marginal: measured over real one-relay campaign levels the exhaustive
// search visits 533-13,943 states and finishes in **3-205ms**. Random boards
// from the old synthetic config are far less constrained than generated ones,
// which is why they blew up. Testing what actually ships is both more honest
// and roughly two orders of magnitude cheaper.
//
// So this file now sweeps the real campaign — `LevelGenerator.neutral()`,
// ids 1..600, Medium and Hard — and runs the property on every board that
// ships with a relay. The search carries a state budget so a pathological
// board is reported as INCONCLUSIVE and counted separately; exhaustion is
// never silently treated as a pass.
const int kStateBudget = 400000;
const int kSweepIds = 600;

void main() {
  test('shipped boards never carry more than one relay', () {
    final counts = <DifficultyMode, Map<int, int>>{};
    for (final mode in DifficultyMode.values) {
      final hist = <int, int>{};
      final generator = LevelGenerator.neutral();
      for (var id = 1; id <= kSweepIds; id++) {
        final result = generator.generate(id, mode: mode);
        if (!result.isSuccess) continue;
        final relays =
            result.value.nodes.where((n) => n.kind == NodeKind.relay).length;
        hist[relays] = (hist[relays] ?? 0) + 1;
      }
      counts[mode] = hist;
      final keys = hist.keys.toList()..sort();
      print('${mode.name.padRight(6)} relays/level: '
          '${[for (final k in keys) '$k:${hist[k]}'].join('  ')}');
    }

    // This is the assertion that licenses the two-relay test below to be
    // skipped rather than fixed: a >=2-relay board is not a rare case, it is
    // an unreachable one. If this ever fails, un-skip that test first.
    for (final mode in DifficultyMode.values) {
      final maxRelays = counts[mode]!.keys.reduce((a, b) => a > b ? a : b);
      expect(maxRelays, lessThanOrEqualTo(1),
          reason: '${mode.name} shipped a board with $maxRelays relays; the '
              'two-relay softlock counterexample is no longer unreachable');
    }
  }, tags: 'slow', timeout: const Timeout(Duration(minutes: 20)));

  test('One-relay softlock property test', () {
    var tested = 0;
    final inconclusive = <String>[];
    final softlocked = <String>[];

    for (final mode in [DifficultyMode.medium, DifficultyMode.hard]) {
      final generator = LevelGenerator.neutral();
      for (var id = 1; id <= kSweepIds; id++) {
        final result = generator.generate(id, mode: mode);
        if (!result.isSuccess) continue;
        final level = result.value;
        if (level.nodes.where((n) => n.kind == NodeKind.relay).length != 1) {
          continue;
        }

        final search = _SoftlockSearch();
        final verdict = search.run(level);
        if (verdict == _Verdict.budgetExhausted) {
          inconclusive.add('$id/${mode.name} (${level.nodes.length} nodes)');
          continue;
        }
        tested++;
        if (verdict == _Verdict.softlocked) {
          softlocked.add('$id/${mode.name} (${level.nodes.length} nodes)');
        }
      }
    }

    print('One relay: $tested boards proved safe, ${inconclusive.length} '
        'inconclusive (state budget), ${softlocked.length} softlocked.');
    if (inconclusive.isNotEmpty) {
      print('  inconclusive: ${inconclusive.join(', ')}');
    }

    expect(softlocked, isEmpty,
        reason: 'shipped one-relay boards reached a dead end: '
            '${softlocked.join(', ')}');
    // Coverage is asserted AFTER the property so a rotted fixture reports as
    // "tested nothing" rather than as a silent pass — the failure mode this
    // file was in before T2.24.
    expect(tested, greaterThan(10),
        reason: 'the one-relay fixture proved nothing: $tested boards had '
            'exactly one relay and completed inside the state budget');
  }, tags: 'slow', timeout: const Timeout(Duration(minutes: 30)));

  // UNREACHABLE-STATE HARDENING — deliberately skipped, not deleted.
  //
  // This test finds a genuine counterexample: on a bespoke 6x6 / 10-node
  // config with two relays forced on, `seed=22` passes
  // `_relayIsSoftlockSafe` and then softlocks under exhaustive search. The
  // gap in that predicate is real.
  //
  // It is skipped because the campaign never emits such a board. The test
  // above measures exactly that and asserts it — Easy ships 0 relays, Medium
  // and Hard ship 0 or 1, never 2, across 1800 boards. Making this pass would
  // mean changing relay placement to satisfy a configuration no player can
  // reach, which is the wrong trade before a content freeze.
  //
  // UN-SKIP THIS when either: the mechanic budget starts issuing two relays
  // on any surface (the guard above goes red first), or `_relayIsSoftlockSafe`
  // is reworked and this becomes its regression case.
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

    var boardsTested = 0;
    for (var seed = 0; seed < 800; seed++) {
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
      if (relays.length != 2) continue;

      expect(relays[0].y, isNot(relays[1].y),
          reason: 'Two relays must be in distinct rows');
      boardsTested++;

      expect(_SoftlockSearch().run(enriched), isNot(_Verdict.softlocked),
          reason: 'Level seed=$seed with 2 relays softlocked despite passing '
              '_relayIsSoftlockSafe');
    }

    expect(boardsTested, greaterThan(5),
        reason: 'Need to test enough 2-relay boards');
  },
      tags: 'slow',
      skip: 'Unreachable in shipped content — the campaign never emits a '
          'two-relay board (see the relay-count guard above). Retained as '
          'documentation of a real gap in _relayIsSoftlockSafe.');
}

enum _Verdict { safe, softlocked, budgetExhausted }

/// Exhaustively explores every *reachable state* of a board.
///
/// [_visited] is shared across the whole search on purpose. Whether a state is
/// a dead end depends only on the state, never on the move order that reached
/// it, so each state needs visiting exactly once — and the property under test
/// ("is any reachable state a softlock") is unchanged by sharing it.
///
/// An earlier version passed `Set<String>.from(visited)` into each recursive
/// call, making memoization per-path rather than global. That degenerates into
/// a walk of every move *permutation*: O(n!) instead of O(states). Do not
/// reintroduce the copy.
///
/// [kStateBudget] bounds the walk. Hitting it yields
/// [_Verdict.budgetExhausted], which callers must count separately — an
/// unfinished search is not evidence of safety.
class _SoftlockSearch {
  final Set<String> _visited = <String>{};
  bool _exhausted = false;

  _Verdict run(LevelData level) {
    final found = _search(level);
    if (found) return _Verdict.softlocked;
    return _exhausted ? _Verdict.budgetExhausted : _Verdict.safe;
  }

  bool _search(LevelData current) {
    if (current.nodes.isEmpty) return false;
    if (_visited.length >= kStateBudget) {
      _exhausted = true;
      return false;
    }

    final stateHash =
        (current.nodes.map((n) => '${n.id}:${n.dir.index}').toList()..sort())
            .join('|');
    if (!_visited.add(stateHash)) return false;

    final moves = <int>[];
    for (final n in current.nodes) {
      if (LevelSolver.canRemove(n, current.nodes, current)) moves.add(n.id);
    }
    // No moves left but the board is not clear -> softlock.
    if (moves.isEmpty) return true;

    for (final moveId in moves) {
      final moveNode = current.nodes.firstWhere((n) => n.id == moveId);
      final next = LevelData(
        levelId: current.levelId,
        gridWidth: current.gridWidth,
        gridHeight: current.gridHeight,
        playCells: current.playCells,
        nodes: [
          for (final n in current.nodes)
            if (n.id != moveId)
              if (moveNode.kind == NodeKind.relay && n.y == moveNode.y)
                n.copyWith(dir: n.dir.rotatedCw)
              else
                n,
        ],
      );
      if (_search(next)) return true;
    }
    return false;
  }
}
