@Tags(['slow'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:chain_pop/game/levels/generation/level_generator.dart';
import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/metrics.dart';
import 'package:chain_pop/game/levels/level.dart';
import 'package:chain_pop/game/levels/level_directive.dart';
import 'package:chain_pop/game/world_registry.dart';

/// Re-runnable diagnostic: does the campaign actually escalate for a player
/// walking Hard 1 -> 1000? Prints a per-sector table of the things a player
/// can feel (board size, node count, mechanic load, decision width, forcedness)
/// and asserts only the things that would be outright bugs.
void main() {
  test('Hard campaign escalation report (1..1000)', () {
    final gen = LevelGenerator(enableDiversityGating: false);

    final perSector = <int, _SectorAcc>{};
    final directiveCounts = <String, int>{};
    final gridCounts = <String, int>{};
    var failures = 0;

    for (var i = 1; i <= 1000; i++) {
      // Use the production time budget: this measures the boards players
      // actually get, not the unbudgeted full-search boards.
      final res = gen.generate(
        i,
        mode: DifficultyMode.hard,
        timeBudget: const Duration(milliseconds: 200),
      );
      if (!res.isSuccess) {
        failures++;
        continue;
      }
      final level = res.value;
      final sector = worldForLevel(i).sector.mechanicBudgetTier;
      final acc = perSector.putIfAbsent(sector, () => _SectorAcc());

      acc.n++;
      acc.nodes += level.nodes.length;

      // LevelMetrics.compute runs the solver and dominates the runtime, so
      // sample it every 5th level. Mechanic counts below are cheap and stay on
      // all 1000.
      if (i % 5 == 0) {
        final m = LevelMetrics.compute(level);
        acc.mn++;
        acc.waves += m.waveDepth;
        acc.fsr += m.forcedSequenceRatio;
        acc.opening += m.firstLegalMoveCount;
        acc.branching += m.averageBranchingFactor;
      }

      acc.cores += level.nodes.where((n) => n.isCore).length;
      acc.locks +=
          level.nodes.where((n) => n.kind == NodeKind.locked).length;
      acc.relays += level.nodes.where((n) => n.kind == NodeKind.relay).length;
      acc.gates += level.nodes
          .map((n) => n.phaseGroup)
          .fold<int>(0, (a, b) => a > b ? a : b);
      acc.portals += level.portalPairs.length;
      acc.mechanicLevels += _hasAnyMechanic(level) ? 1 : 0;

      final d = directiveFor(levelId: i, mode: DifficultyMode.hard);
      directiveCounts[d.label] = (directiveCounts[d.label] ?? 0) + 1;
      final g = '${level.gridWidth}x${level.gridHeight}';
      gridCounts[g] = (gridCounts[g] ?? 0) + 1;
    }

    // ignore: avoid_print
    print('\n=== HARD CAMPAIGN ESCALATION (1..1000) ===');
    // ignore: avoid_print
    print('generation failures: $failures / 1000');
    // ignore: avoid_print
    print('Sec |   n | nodes | waves |  FSR  | open | branch | core | lock '
        '| relay | gate | portal | %mech');
    final sectors = perSector.keys.toList()..sort();
    for (final s in sectors) {
      final a = perSector[s]!;
      // ignore: avoid_print
      print('  $s | ${a.n.toString().padLeft(3)} | '
          '${_f(a.nodes / a.n, 5)} | ${_f(a.waves / a.mn, 5)} | '
          '${(a.fsr / a.mn).toStringAsFixed(3)} | ${_f(a.opening / a.mn, 4)} | '
          '${_f(a.branching / a.mn, 6)} | ${_f(a.cores / a.n, 4)} | '
          '${_f(a.locks / a.n, 4)} | ${_f(a.relays / a.n, 5)} | '
          '${_f(a.gates / a.n, 4)} | ${_f(a.portals / a.n, 6)} | '
          '${(100 * a.mechanicLevels / a.n).toStringAsFixed(0)}%');
    }
    // ignore: avoid_print
    print('\ndirectives: $directiveCounts');
    // ignore: avoid_print
    print('grids: $gridCounts');

    // Hard assertions: only genuine bugs.
    expect(failures, 0, reason: 'every Hard level 1..1000 must generate');

    // The campaign must actually escalate: late sectors carry strictly more
    // mechanic load than sector 1.
    final first = perSector[1]!;
    final last = perSector[sectors.last]!;
    expect(last.mechanicLoad / last.n,
        greaterThan(first.mechanicLoad / first.n),
        reason: 'late sectors must carry more mechanic load than sector 1');
  });
}

bool _hasAnyMechanic(LevelData level) =>
    level.portalPairs.isNotEmpty ||
    level.nodes.any((n) =>
        n.kind == NodeKind.locked ||
        n.kind == NodeKind.relay ||
        n.phaseGroup > 0);

String _f(num v, int w) => v.toStringAsFixed(2).padLeft(w);

class _SectorAcc {
  int n = 0;

  /// Levels in this sector that had full metrics computed (the 1-in-5 sample).
  int mn = 0;
  int nodes = 0;
  int waves = 0;
  double fsr = 0;
  int opening = 0;
  double branching = 0;
  int cores = 0;
  int locks = 0;
  int relays = 0;
  int gates = 0;
  int portals = 0;
  int mechanicLevels = 0;

  int get mechanicLoad => locks + relays + gates + portals;
}
