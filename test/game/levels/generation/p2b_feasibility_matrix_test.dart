// P2b T2.13 — the Hard feasibility matrix.
//
//   flutter test --tags report \
//     test/game/levels/generation/p2b_feasibility_matrix_test.dart
//
// **Asserts nothing**, by construction.
//
// WHY THIS EXISTS. Every proposed streak-breaker so far has needed a prior for
// "which silhouettes can the Director actually reach for on Hard", and every
// one has guessed it. One draft excluded `cross` as known-doomed; the shipped
// sweep emits cross 60 times per 300 Hard levels, making it one of the most
// feasible shapes there is. A forced pick of a genuinely infeasible shape does
// not break a streak — it fails its mask, falls through the recovery ladder,
// and lands back on lattice, burning attempts to change nothing.
//
// THREE LAYERS, because "fits the cell band" is not "is a good Hard board":
//
//   1. MASK LAYER   — can the shape be built at 8x8 at all, and does its area
//                     land in the Director's [target, target*kMaskAreaSlack]
//                     window? Pure geometry, no generation.
//   2. ROUTING      — on the real shipped path, when this id is REQUESTED, how
//                     often does it survive as itself vs. convert to another
//                     family? Answers "will a forced pick actually ship?"
//   3. DIFFICULTY   — for boards that DO ship with this id, what is the FSR /
//                     branching / node profile? A shape can build, survive
//                     routing, and still distort the difficulty envelope — the
//                     Daily in-band regression after the rectangle purge was
//                     exactly this: sparser organic masks raising FSR past the
//                     expert 0.85 ceiling.
//
// The verdict column is deliberately three-valued, not a binary feasible flag,
// so the scheduler can prefer a GREEN novel choice over a YELLOW one without
// anybody maintaining a hardcoded blacklist.
//
// ignore_for_file: avoid_print

@Tags(['report'])
library;

import 'dart:math';

import 'package:chain_pop/game/levels/analytics/generation_analytics.dart';
import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/director.dart';
import 'package:chain_pop/game/levels/generation/level_generator.dart';
import 'package:chain_pop/game/levels/generation/metrics.dart';
import 'package:chain_pop/game/levels/generation/silhouettes.dart';
import 'package:flutter_test/flutter_test.dart';

import 'board_report_utils.dart';

/// Hard ships ~25 nodes on 8x8; the Director accepts a mask up to
/// `targetNodeCount * kMaskAreaSlack` before `_refinePlanMaskDensity` swaps it
/// for a dense one. That makes [25, 38] the window a Hard mask must hit.
const int kHardTarget = 25;
const int kHardMaxArea = 38; // (25 * kMaskAreaSlack=1.5).ceil()
const int kMaskRolls = 400;
const int kSweepLevels = 300;

void main() {
  test('P2b Hard feasibility matrix', () {
    _maskLayer();
    _productionLayers();
  }, timeout: const Timeout(Duration(minutes: 30)));
}

// ---------------------------------------------------------------- layer 1
void _maskLayer() {
  print('=== LAYER 1 — MASK GEOMETRY (8x8, $kMaskRolls rolls/id) ===');
  print('band = [$kHardTarget, $kHardMaxArea] cells '
      '(Hard target .. target*kMaskAreaSlack)');
  print('${'id'.padRight(13)}${'family'.padRight(17)}'
      '${'build'.padLeft(7)}${'inBand'.padLeft(8)}'
      '${'p10'.padLeft(6)}${'med'.padLeft(6)}${'p90'.padLeft(6)}'
      '   dominant miss');
  for (final id in SilhouetteId.values) {
    final random = Random(20260822);
    var built = 0;
    var inBand = 0;
    var under = 0;
    var over = 0;
    final cells = <int>[];
    for (var i = 0; i < kMaskRolls; i++) {
      final m = buildSilhouetteMask(
        id: id,
        gridWidth: 8,
        gridHeight: 8,
        random: random,
      );
      if (m == null) continue;
      built++;
      cells.add(m.length);
      if (m.length < kHardTarget) {
        under++;
      } else if (m.length > kHardMaxArea) {
        over++;
      } else {
        inBand++;
      }
    }
    cells.sort();
    int q(double f) => cells.isEmpty
        ? 0
        : cells[(cells.length * f).floor().clamp(0, cells.length - 1)];
    final miss = under == 0 && over == 0
        ? '-'
        : (under >= over
            ? 'too small ($under)'
            : 'too large ($over)');
    print('${id.name.padRight(13)}'
        '${silhouetteVisualFamily(id).name.padRight(17)}'
        '${_pct(built, kMaskRolls).padLeft(7)}'
        '${_pct(inBand, kMaskRolls).padLeft(8)}'
        '${q(0.10).toString().padLeft(6)}'
        '${q(0.50).toString().padLeft(6)}'
        '${q(0.90).toString().padLeft(6)}'
        '   $miss');
  }
}

// ------------------------------------------------------------- layers 2+3
void _productionLayers() {
  // Per REQUESTED id: where the resolution ladder took it.
  final requested = <SilhouetteId, int>{};
  final survived = <SilhouetteId, int>{};
  final sameId = <SilhouetteId, int>{};
  final converted = <SilhouetteId, int>{};
  final director = Director(
    onSilhouetteRouted: (req, res, stage) {
      requested[req] = (requested[req] ?? 0) + 1;
      if (res == req) sameId[req] = (sameId[req] ?? 0) + 1;
      // NOTE: family-level survival is trivially 100% for any lattice id — the
      // density recovery pool is all-lattice, so a lattice request that loses
      // its exact shape still "survives" by family. `sameId` is the honest
      // column for lattice; family survival is the honest one for the rest.
      if (silhouetteVisualFamily(res) == silhouetteVisualFamily(req)) {
        survived[req] = (survived[req] ?? 0) + 1;
      } else {
        converted[req] = (converted[req] ?? 0) + 1;
      }
    },
  );

  final sink = InMemoryAnalyticsSink();
  final gen = LevelGenerator(director: director, analyticsSink: sink);
  final shippedMetrics = <SilhouetteId, List<LevelMetrics>>{};
  for (var id = 1; id <= kSweepLevels; id++) {
    final r = gen.generate(id, mode: DifficultyMode.hard,
        timeBudget: kProdBudget);
    if (!r.isSuccess) continue;
    if (sink.events.isEmpty) continue;
    final sid = sink.events.last.silhouette;
    shippedMetrics
        .putIfAbsent(sid, () => <LevelMetrics>[])
        .add(LevelMetrics.compute(r.value));
  }

  print('');
  print('=== LAYERS 2+3 — ROUTING SURVIVAL & SHIPPED DIFFICULTY '
      '(Hard L1-$kSweepLevels) ===');
  print('${'id'.padRight(13)}${'req'.padLeft(6)}${'sameId'.padLeft(8)}'
      '${'famOK'.padLeft(8)}'
      '${'ship'.padLeft(6)}${'nodes'.padLeft(7)}${'FSR'.padLeft(7)}'
      '${'BF'.padLeft(6)}   verdict');
  for (final id in SilhouetteId.values) {
    final req = requested[id] ?? 0;
    final surv = survived[id] ?? 0;
    final ms = shippedMetrics[id] ?? const <LevelMetrics>[];
    final n = ms.length;
    final nodes = n == 0
        ? 0.0
        : ms.map((m) => m.nodeCount).reduce((a, b) => a + b) / n;
    final fsr = n == 0
        ? 0.0
        : ms.map((m) => m.forcedSequenceRatio).reduce((a, b) => a + b) / n;
    final bf = n == 0
        ? 0.0
        : ms
                .map((m) => m.averageBranchingFactor)
                .reduce((a, b) => a + b) /
            n;
    // GREEN  reliably survives routing AND ships a sane difficulty profile.
    // YELLOW ships, but thinly or with a strained profile.
    // RED    effectively never reaches a player on Hard.
    final survRate = req == 0 ? 0.0 : (sameId[id] ?? 0) / req;
    String verdict;
    if (n == 0) {
      verdict = 'RED    never ships';
    } else if (survRate < 0.75 || n < 10) {
      verdict = 'YELLOW thin/fragile';
    } else if (fsr > 0.85) {
      verdict = 'YELLOW FSR over expert ceiling';
    } else {
      verdict = 'GREEN';
    }
    print('${id.name.padRight(13)}${req.toString().padLeft(6)}'
        '${_pct(sameId[id] ?? 0, req).padLeft(8)}'
        '${_pct(surv, req).padLeft(8)}${n.toString().padLeft(6)}'
        '${nodes.toStringAsFixed(1).padLeft(7)}'
        '${(fsr * 100).toStringAsFixed(0).padLeft(6)}%'
        '${bf.toStringAsFixed(2).padLeft(6)}   $verdict');
  }
}

String _pct(int a, int b) =>
    b == 0 ? '-' : '${(100 * a / b).toStringAsFixed(0)}%';
