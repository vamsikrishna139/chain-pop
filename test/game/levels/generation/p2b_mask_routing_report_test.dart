// P2b T2.11 — did closing the one-way lattice valve change what ships?
//
//   flutter test --tags report \
//     test/game/levels/generation/p2b_mask_routing_report_test.dart
//
// **Asserts nothing**, by construction (plan §0.5).
//
// The visual review of Hard L30-80 returned "repetitive": 3 families across 51
// boards, 37 lattice (72.5%), 12 organic, 2 corridor, 0 archipelago, 6 plain
// rectangles. The mask-layer probe found why, and it was not the 40% dense
// coin-flip in `_pickSilhouette`. At 8x8 against Hard's 25-cell floor:
//
//   archipelago  fails to build 109/200 rolls,  in-band  2/200
//   corridor     fails to build  75/200 rolls,  in-band 50/200
//   rectangle    always 64 cells,               in-band  0/200
//   diamond      fails to build  71/200 rolls,  in-band 116/200
//
// A failed build returned the *full rectangle*, which always overshoots
// `kMaskAreaSlack`, which sent the plan into `_refinePlanMaskDensity`, whose
// recovery pool was `_denseSilhouettes` — ring/cross/diamond/rectangle, 100%
// geometricLattice, with diamond as the only reliable in-band member. Every
// mask failure therefore became a lattice board.
//
// Two views:
//
//   1. WHAT SHIPS — emitted family shares, longest same-family run, plain
//      rectangles and distinct outlines, on the review window (Hard L30-80)
//      and the wider L1-300 sweep. Medium is a control.
//   2. THE CONVERSION MATRIX — requested family -> resolved family, over every
//      mask resolution the run performed. This is the view that separates the
//      two ways lattice share can fall: "the requested shapes became feasible"
//      and "the fallback stopped converting them" are indistinguishable from
//      the emitted boards alone, and they imply different follow-up work.
//
// ignore_for_file: avoid_print

@Tags(['report'])
library;

import 'package:chain_pop/game/levels/generation/archetype.dart';
import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/director.dart';
import 'package:chain_pop/game/levels/generation/level_generator.dart';
import 'package:chain_pop/game/levels/analytics/generation_analytics.dart';
import 'package:chain_pop/game/levels/generation/silhouettes.dart';
import 'package:chain_pop/game/levels/level.dart';
import 'package:flutter_test/flutter_test.dart';

import 'board_report_utils.dart';

const int kSweepLevels = 300;
const int kReviewFrom = 30;
const int kReviewTo = 80;

void main() {
  test('P2b mask routing report', () {
    _sweep(DifficultyMode.hard);
    print('');
    _sweep(DifficultyMode.medium);
  }, timeout: const Timeout(Duration(minutes: 30)));
}

void _sweep(DifficultyMode mode) {
  final routes = <MaskRouteStage, int>{};
  final matrix = <String, int>{};
  // Pick-time: one event per `_pickSilhouette` draw, NOT per mask resolution.
  // This is the layer the archetype-pool purge changes, and the only one whose
  // predicted rate (Hard: 78.1% lattice / 35.2% rectangle) is falsifiable.
  var picks = 0;
  var pickLattice = 0;
  var pickRectangle = 0;
  var pickDenseBranch = 0;
  final pickByArchetype = <GenerationArchetype, List<int>>{};
  final director = Director(
    onSilhouetteRouted: (requested, resolved, stage) {
      routes[stage] = (routes[stage] ?? 0) + 1;
      final key = '${silhouetteVisualFamily(requested).name}'
          ' -> ${silhouetteVisualFamily(resolved).name}';
      matrix[key] = (matrix[key] ?? 0) + 1;
    },
    onSilhouettePicked: (archetype, requested, denseBranchTaken) {
      picks++;
      final isLattice = silhouetteVisualFamily(requested) ==
          SilhouetteVisualFamily.geometricLattice;
      final isRect = requested == SilhouetteId.rectangle;
      if (isLattice) pickLattice++;
      if (isRect) pickRectangle++;
      if (denseBranchTaken) pickDenseBranch++;
      final row = pickByArchetype.putIfAbsent(archetype, () => [0, 0, 0]);
      row[0]++;
      if (isLattice) row[1]++;
      if (isRect) row[2]++;
    },
  );
  // Sequential campaign run on one generator: the ledger and the silhouette
  // tracker carry across levels, which is how boards actually reach players.
  final sink = InMemoryAnalyticsSink();
  final gen = LevelGenerator(director: director, analyticsSink: sink);

  final emitted = <int, LevelData>{};
  final shipped = <int, SilhouetteId>{};
  final micros = <int>[];
  for (var id = 1; id <= kSweepLevels; id++) {
    final sw = Stopwatch()..start();
    final r = gen.generate(id, mode: mode, timeBudget: kProdBudget);
    sw.stop();
    micros.add(sw.elapsedMicroseconds);
    if (!r.isSuccess) continue;
    emitted[id] = r.value;
    // The emitted plan's silhouette: `LevelData.silhouetteId` is non-null only
    // for seeded boards, so the analytics event is the shipped-path source.
    if (sink.events.isNotEmpty) shipped[id] = sink.events.last.silhouette;
  }

  final label = mode.name.toUpperCase();
  print('=== $label — WHAT SHIPS (sequential, prod budget) ===');
  _window(emitted, shipped, kReviewFrom, kReviewTo,
      '$label L$kReviewFrom-$kReviewTo');
  _window(emitted, shipped, 1, kSweepLevels, '$label L1-$kSweepLevels');

  micros.sort();
  final p95 = micros[(micros.length * 0.95).floor().clamp(0, micros.length - 1)];
  print('generation p95: ${(p95 / 1000).toStringAsFixed(0)} ms   '
      'emitted ${emitted.length}/$kSweepLevels');

  print('--- $label PICK-TIME REQUESTS (one event per _pickSilhouette) ---');
  final pctL = picks == 0 ? 0.0 : 100 * pickLattice / picks;
  final pctR = picks == 0 ? 0.0 : 100 * pickRectangle / picks;
  final pctD = picks == 0 ? 0.0 : 100 * pickDenseBranch / picks;
  print('  picks=$picks   requested lattice ${pctL.toStringAsFixed(1)}%   '
      'requested rectangle ${pctR.toStringAsFixed(1)}%   '
      'dense branch taken ${pctD.toStringAsFixed(1)}%');
  for (final a in GenerationArchetype.values) {
    final row = pickByArchetype[a];
    if (row == null || row[0] == 0) continue;
    final n = row[0];
    print('    ${a.name.padRight(16)} n=${n.toString().padLeft(5)}  '
        'lattice ${(100 * row[1] / n).toStringAsFixed(1)}%  '
        'rectangle ${(100 * row[2] / n).toStringAsFixed(1)}%');
  }

  print('--- $label CONVERSION MATRIX (all mask resolutions) ---');
  final stages = MaskRouteStage.values
      .map((s) => '${s.name}=${routes[s] ?? 0}')
      .join('  ');
  print('route stage: $stages');
  final rows = matrix.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final total = matrix.values.fold<int>(0, (a, b) => a + b);
  for (final e in rows) {
    final pct = total == 0 ? 0.0 : 100 * e.value / total;
    final converted = !e.key.startsWith(e.key.split(' -> ').last);
    print('  ${e.key.padRight(42)} ${e.value.toString().padLeft(5)}  '
        '${pct.toStringAsFixed(1)}%${converted ? '   <- converted' : ''}');
  }
}

void _window(
  Map<int, LevelData> emitted,
  Map<int, SilhouetteId> shipped,
  int from,
  int to,
  String label,
) {
  final seq = <SilhouetteVisualFamily>[];
  // T2.19 — what the PLAYER sees, not what the plan was labelled. A board
  // whose `playCells` is null renders as a plain full grid no matter which
  // silhouette id produced it, so for review purposes it IS a rectangle.
  // Measured on Hard L30-80: L45 ships full-grid labelled `diamond` and L55
  // full-grid labelled `corridor`, and the label-based counter scored the
  // latter as one of the corridor boards.
  final seqVisible = <SilhouetteVisualFamily>[];
  final ids = <SilhouetteId>[];
  final outlines = <String>{};
  var plainRect = 0;
  var plainRectLabelled = 0;
  for (var id = from; id <= to; id++) {
    final level = emitted[id];
    if (level == null) continue;
    final sid = shipped[id];
    if (sid == null) continue;
    ids.add(sid);
    seq.add(silhouetteVisualFamily(sid));
    seqVisible.add(level.playCells == null
        ? SilhouetteVisualFamily.geometricLattice
        : silhouetteVisualFamily(sid));
    outlines.add(level.playCells == null
        ? 'FULL:${level.gridWidth}x${level.gridHeight}'
        : (level.playCells!.toList()..sort()).join('|'));
    // Geometry alone. The old predicate also required the id to be
    // `rectangle`, which undercounted every full grid that arrived under
    // another label.
    if (level.playCells == null) plainRect++;
    if (sid == SilhouetteId.rectangle && level.playCells == null) plainRectLabelled++;
  }
  final counts = <SilhouetteVisualFamily, int>{};
  for (final f in seq) {
    counts[f] = (counts[f] ?? 0) + 1;
  }
  int longestRun(List<SilhouetteVisualFamily> xs) {
    var best = 0, run = 0;
    SilhouetteVisualFamily? prev;
    for (final f in xs) {
      run = (f == prev) ? run + 1 : 1;
      prev = f;
      if (run > best) best = run;
    }
    return best;
  }

  final longest = longestRun(seq);
  final longestVisible = longestRun(seqVisible);
  final visibleCounts = <SilhouetteVisualFamily, int>{};
  for (final f in seqVisible) {
    visibleCounts[f] = (visibleCounts[f] ?? 0) + 1;
  }
  final n = seq.length;
  final shares = SilhouetteVisualFamily.values
      .map((f) => '${f.name} ${counts[f] ?? 0}'
          ' (${n == 0 ? 0 : (100 * (counts[f] ?? 0) / n).round()}%)')
      .join('  ');
  print('--- $label  n=$n ---');
  print('  families present  : ${counts.keys.length}/4');
  print('  family shares     : $shares');
  print('  longest same-family run : $longest'
      '   (player-visible: $longestVisible)');
  print('  families present  : ${visibleCounts.keys.length}/4  <- player-visible');
  print('  PLAIN RECTANGLES  : $plainRect'
      ' (${n == 0 ? 0 : (100 * plainRect / n).toStringAsFixed(1)}%)'
      '   [label-only counter said $plainRectLabelled'
      ' (${n == 0 ? 0 : (100 * plainRectLabelled / n).toStringAsFixed(1)}%)]');
  print('  distinct outlines : ${outlines.length}');
  final idCounts = <SilhouetteId, int>{};
  for (final i in ids) {
    idCounts[i] = (idCounts[i] ?? 0) + 1;
  }
  print('  ids               : ${idCounts.entries.map((e) => '${e.key.name}=${e.value}').join('  ')}');
}
