// Gen V2 gates G1b, G2, G3, G4, G5 (docs/GEN_V2_PLAN.md).
//
//   flutter test test/game/levels/generation/v2/gen_v2_gate_test.dart
//   V2_N=100 flutter test ...   (smaller sample while iterating)
//
// Prints a summary table, then asserts each gate. A red gate is a finding to
// record in the plan, never a threshold to loosen in place.
// ignore_for_file: avoid_print
@Tags(['corpus'])
library;

import 'dart:io';
import 'dart:math';

import 'package:chain_pop/game/chain_pop_game.dart';
import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/difficulty_profile.dart';
import 'package:chain_pop/game/levels/generation/level_generator.dart';
import 'package:chain_pop/game/levels/generation/visual_composition.dart';
import 'package:chain_pop/game/levels/level.dart';
import 'package:chain_pop/game/levels/level_manager.dart';
import 'package:chain_pop/game/world_registry.dart';
import 'package:flutter_test/flutter_test.dart';

import '../board_report_utils.dart';
import 'board_fingerprint.dart';

const _kRoutes = 3;

class _Gen {
  _Gen(this.level, this.ms, this.label);
  final LevelData? level;
  final int ms;
  final String label;
}

/// Generated exactly as `LevelManager` ships V2: a fresh generator per level,
/// so the board is a function of the level id alone.
List<_Gen> _runHard(int n, {bool reverse = false}) {
  final ids = [for (var id = 1; id <= n; id++) id];
  final out = [
    for (final id in reverse ? ids.reversed : ids)
      () {
        final sw = Stopwatch()..start();
        final r = LevelGenerator.neutral().generate(id,
            mode: DifficultyMode.hard,
            workBudget: LevelManager.genV2WorkBudget,
            generationVersion: 2);
        return _Gen(r.isSuccess ? r.value : null, sw.elapsedMilliseconds,
            'hard L$id');
      }(),
  ];
  return reverse ? out.reversed.toList() : out;
}

List<_Gen> _runDaily(int n) => [
      for (var i = 0; i < n; i++)
        () {
          final d = DateTime(2026, 12, 1).add(Duration(days: i));
          final key = d.year * 10000 + d.month * 100 + d.day;
          final sw = Stopwatch()..start();
          final r = LevelGenerator.neutral().generateDailyChallenge(key,
              workBudget: LevelManager.dailyWorkBudget, generationVersion: 2);
          return _Gen(r.isSuccess ? r.value : null, sw.elapsedMilliseconds,
              'daily $key');
        }(),
    ];

/// Random-route autoplay through the real engine, as the soft-lock guard does.
String? _deadEnd(LevelData level, DifficultyMode mode, int seed) {
  for (var route = 0; route < _kRoutes; route++) {
    var won = false;
    final game = ChainPopGame(
        levelId: level.levelId, difficulty: mode, onWin: () => won = true);
    game.levelData = level;
    game.activeNodes.addAll(level.nodes.map((n) => n.clone()));
    game.refreshExtractableIdsForTest();
    final rng = Random(seed * 1000 + route);
    var taps = 0;
    while (!game.hasWon && taps < level.nodes.length + 8) {
      final c = [
        for (final n in game.activeNodes)
          if (game.canExtract(n)) n
      ];
      if (c.isEmpty) break;
      game.registerExtraction(c[rng.nextInt(c.length)]);
      taps++;
    }
    if (!game.hasWon && !won) return 'route $route stuck after $taps taps';
  }
  return null;
}

double _pct(List<num> v, double p) {
  final s = [...v]..sort();
  return s[((s.length - 1) * p).round()].toDouble();
}

void main() {
  final n = int.tryParse(Platform.environment['V2_N'] ?? '') ?? 300;
  final nDaily = (n ~/ 5).clamp(10, 60);

  test('Gen V2 gates (Hard L1..$n + $nDaily dailies)', () {
    final hard = _runHard(n);
    final daily = _runDaily(nDaily);

    // ── G1b determinism: a second run, in the opposite order, is
    // byte-identical — no board depends on what was generated before it ──
    final again = _runHard(min(n, 100), reverse: true);
    final nondet = <String>[
      for (var i = 0; i < again.length; i++)
        if ((hard[i].level == null) != (again[i].level == null) ||
            (hard[i].level != null &&
                boardFingerprint(hard[i].level!) !=
                    boardFingerprint(again[i].level!)))
          hard[i].label
    ];

    // ── G3 validity + solvability ──
    final failed = <String>[];
    final stuck = <String>[];
    for (final g in [...hard, ...daily]) {
      final l = g.level;
      if (l == null) {
        failed.add('${g.label}: generation failed');
        continue;
      }
      final layout = LevelData.layoutValidationMessage(l);
      if (layout != null) failed.add('${g.label}: $layout');
      const mode = DifficultyMode.hard;
      final dead = _deadEnd(l, mode, l.levelId);
      if (dead != null) stuck.add('${g.label}: $dead');
    }

    // ── G4/G5 measurement on Hard ──
    final rows = <BoardRow>[];
    for (final g in hard) {
      final l = g.level;
      if (l == null) continue;
      final world = worldForLevel(l.levelId);
      rows.add(measure(l,
          label: g.label,
          levelId: l.levelId,
          mode: DifficultyMode.hard,
          // G5 judges V2 on the evaluator V2 actually uses.
          profile: DifficultyProfile.hard.scaledForGenV2(l.nodes.length),
          directive: '-',
          timeLimitSec: 0,
          genMs: g.ms,
          sector: world.sector.mechanicBudgetTier,
          worldName: world.name));
    }
    final nodes = [for (final r in rows) r.nodes];
    final cover = [for (final r in rows) r.boardCoveragePct];
    final cell = [for (final r in rows) r.cellPx];
    final empty = [for (final r in rows) r.screenEmptyPct];
    final taps = [for (final r in rows) r.tapsToWin];
    final opening = [for (final r in rows) r.metrics.firstLegalMoveCount];
    final inBand = rows.where((r) => r.inBand).length;
    final cell44 = cell.where((c) => c >= 44).length;
    final hardMs = [for (final g in hard) g.ms];
    final dailyMs = [for (final g in daily) g.ms];
    final grids = <String, int>{};
    for (final r in rows) {
      grids.update('${r.gridW}x${r.gridH}', (v) => v + 1, ifAbsent: () => 1);
    }

    print('\n===== GEN V2 GATES  (Hard L1..$n, $nDaily dailies) =====');
    print('  grids            $grids');
    print('  nodes            min ${nodes.reduce(min)}  p50 ${_pct(nodes, .5)}'
        '  max ${nodes.reduce(max)}');
    print('  cover %          p50 ${_pct(cover, .5).toStringAsFixed(1)}'
        '  min ${cover.reduce(min).toStringAsFixed(1)}');
    print('  screen empty %   p50 ${_pct(empty, .5).toStringAsFixed(1)}');
    print('  cell px          p50 ${_pct(cell, .5).toStringAsFixed(1)}'
        '  >=44: $cell44/${rows.length}');
    print('  taps-to-win      p50 ${_pct(taps, .5)}  min ${taps.reduce(min)}');
    print('  opening          p50 ${_pct(opening, .5)}'
        '  range ${opening.reduce(min)}-${opening.reduce(max)}');
    // M1 depth metrics (docs/GEN_V2_PLAN.md §5): reported, not yet gated.
    final coreFrac = [for (final r in rows) r.core.coreTapFraction];
    final tapsPerNode = [
      for (final r in rows) r.tapsToWin / max(1, r.nodes)
    ];
    final hist = <String, int>{};
    for (final o in opening) {
      final b = o <= 5 ? '<=5' : o <= 8 ? '6-8' : o <= 11 ? '9-11' : '12+';
      hist.update(b, (v) => v + 1, ifAbsent: () => 1);
    }
    print('  core-relevant    p25 ${_pct(coreFrac, .25).toStringAsFixed(2)}'
        '  p50 ${_pct(coreFrac, .5).toStringAsFixed(2)}'
        '  p75 ${_pct(coreFrac, .75).toStringAsFixed(2)}');
    print('  taps/nodes       p50 ${_pct(tapsPerNode, .5).toStringAsFixed(2)}');
    print('  opening hist     $hist');
    final dark = [
      for (final g in hard)
        if (g.level != null) genV2LargestDarkRectFraction(g.level!)
    ];
    print('  dark rect frac   p50 ${_pct(dark, .5).toStringAsFixed(2)}'
        '  max ${dark.reduce(max).toStringAsFixed(2)}'
        '  >0.25: ${dark.where((d) => d > kGenV2MaxDarkRectFraction).length}');
    final voids = [
      for (final g in hard)
        if (g.level != null) genV2LargestVoidRegionFraction(g.level!)
    ];
    print('  void region frac p50 ${_pct(voids, .5).toStringAsFixed(2)}'
        '  p90 ${_pct(voids, .9).toStringAsFixed(2)}'
        '  max ${voids.reduce(max).toStringAsFixed(2)}'
        '  >0.25: ${voids.where((d) => d > kGenV2MaxVoidRegionFraction).length}');
    final density = [
      for (final g in hard)
        if (g.level != null)
          g.level!.nodes.length /
              (g.level!.playCells?.length ??
                  g.level!.gridWidth * g.level!.gridHeight)
    ];
    print('  nodes/mask cell  p10 ${_pct(density, .1).toStringAsFixed(2)}'
        '  p50 ${_pct(density, .5).toStringAsFixed(2)}'
        '  min ${density.reduce(min).toStringAsFixed(2)}');
    print('  in-band          $inBand/${rows.length}');
    print('  gen ms hard      p50 ${_pct(hardMs, .5)}  p95 ${_pct(hardMs, .95)}'
        '  max ${hardMs.reduce(max)}');
    print('  gen ms daily     p50 ${_pct(dailyMs, .5)}  p95 ${_pct(dailyMs, .95)}'
        '  max ${dailyMs.reduce(max)}');
    print('  failed ${failed.length}  stuck ${stuck.length}  '
        'nondeterministic ${nondet.length}');
    for (final r in rows.where((r) => r.nodes < 28)) {
      print('    low-node: ${r.label} ${r.nodes} nodes ${r.gridW}x${r.gridH}');
    }
    for (final f in [...failed, ...stuck, ...nondet].take(15)) {
      print('    ! $f');
    }

    expect(nondet, isEmpty, reason: 'G1b determinism');
    expect(failed, isEmpty, reason: 'G3 validity');
    expect(stuck, isEmpty, reason: 'G3 solvability');
    expect(_pct(hardMs, .95), lessThanOrEqualTo(300), reason: 'G2 p95');
    expect([...hardMs, ...dailyMs].reduce(max), lessThanOrEqualTo(1500),
        reason: 'G2 max');
    expect(nodes.reduce(min), greaterThanOrEqualTo(28), reason: 'G4 min');
    expect(_pct(nodes, .5), inInclusiveRange(30, 36), reason: 'G4 median');
    expect(_pct(cover, .5), greaterThanOrEqualTo(70), reason: 'G4 cover');
    expect(cell44 / rows.length, greaterThanOrEqualTo(0.95),
        reason: 'G4 cell');
    expect(inBand / rows.length, greaterThanOrEqualTo(0.90), reason: 'G5');
    expect(dark.where((d) => d > kGenV2MaxDarkRectFraction).length / dark.length,
        lessThanOrEqualTo(0.05),
        reason: 'G10 dark rectangle');
  }, timeout: const Timeout(Duration(minutes: 60)));
}
