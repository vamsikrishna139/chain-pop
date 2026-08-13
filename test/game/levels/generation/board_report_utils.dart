// Shared reporting harness for the wide-sample board snapshot tests.
//
// Diagnostic only: prints a human-readable per-level picture plus batch
// aggregates, and writes a CSV next to it for offline slicing. Nothing here
// asserts quality bands — the audit tests own that.
// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math';

import 'package:chain_pop/game/board_layout.dart';
import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/difficulty_profile.dart';
import 'package:chain_pop/game/levels/generation/level_generator.dart';
import 'package:chain_pop/game/levels/generation/metrics.dart';
import 'package:chain_pop/game/levels/level.dart';
import 'package:chain_pop/game/levels/level_directive.dart';
import 'package:chain_pop/game/world_registry.dart';
import 'package:chain_pop/screens/game/game_time_limit.dart';

/// Fixed reference canvas for cell-space emptiness. Every board observed in
/// these samples fits inside 10×10 (dailies clamp at 8, campaign grids peak at
/// 10×10 on showcase ids), so emptiness against this **fixed** canvas is
/// comparable across boards of different grid sizes. Boards bigger than this
/// are flagged in the per-level line with `OVERSIZE`.
const int kCanvasSpan = 10;
const int kCanvasCells = kCanvasSpan * kCanvasSpan;

/// Reference phone screen used for the pixel-space "how empty is the screen"
/// numbers: 390×844 logical px (iPhone 14/15 class), with the same HUD reserves
/// and margin [ChainPopGame] uses. The playfield band is what the player sees
/// as "the board area"; the board is scaled to fit inside it.
///
/// **The reserves are the ones the app actually applies at runtime**, not the
/// [ChainPopGame] constructor defaults (140/92). Those defaults only survive
/// until the first post-frame HUD measurement; `GamePlayfieldInsetController`
/// then replaces them with `headerBottom + 20` / `(screenH − footerTop) + 16`.
/// Measuring against the defaults under-reported emptiness, because the real
/// band is ~50px shorter. The values below are produced by
/// `test/screens/playfield_insets_reference_test.dart`, which pumps a real
/// [GameScreen] at each device size and asserts these constants stay in sync.
const double kRefScreenW = 390;
const double kRefScreenH = 844;
const double kRefTopReserved = 172;
const double kRefBottomReserved = 110;

/// Second reference device (iPhone 15 Pro Max class, safeTop 59).
const double kRefScreenWLarge = 430;
const double kRefScreenHLarge = 932;
const double kRefTopReservedLarge = 184;
const double kRefBottomReservedLarge = 110;

const double kRefMargin = 24;
const double kBandW = kRefScreenW - kRefMargin * 2;
const double kBandH =
    kRefScreenH - kRefTopReserved - kRefBottomReserved - kRefMargin;
const double kBandArea = kBandW * kBandH;

/// Fraction of the cell the node sprite paints (`NodeComponent`'s
/// `size = cellSize * 0.82`). Before P2 this doubled as the tap target.
const double kNodeVisualScale = 0.82;

/// The single fill the app shipped before P1 — kept as the historical baseline
/// column in the fitter sweep. [FitterVariant.current] models it;
/// [FitterVariant.perAxis] models what ships now, and
/// `board_report_baseline_test.dart` asserts both against the real fitter.
const double kLegacyBoardFill = 0.80;

/// A screen the corpus can be re-measured against.
class ReferenceDevice {
  const ReferenceDevice({
    required this.name,
    required this.screenW,
    required this.screenH,
    required this.topReserved,
    required this.bottomReserved,
    this.margin = kRefMargin,
  });

  final String name;
  final double screenW;
  final double screenH;
  final double topReserved;
  final double bottomReserved;
  final double margin;

  double get bandW => screenW - margin * 2;
  double get bandH => screenH - topReserved - bottomReserved - margin;
  double get bandArea => bandW * bandH;

  static const ReferenceDevice iphone390 = ReferenceDevice(
    name: '390x844',
    screenW: kRefScreenW,
    screenH: kRefScreenH,
    topReserved: kRefTopReserved,
    bottomReserved: kRefBottomReserved,
  );

  static const ReferenceDevice iphone430 = ReferenceDevice(
    name: '430x932',
    screenW: kRefScreenWLarge,
    screenH: kRefScreenHLarge,
    topReserved: kRefTopReservedLarge,
    bottomReserved: kRefBottomReservedLarge,
  );

  static const List<ReferenceDevice> all = [iphone390, iphone430];
}

/// An alternative parameterisation of the board fitter, so the corpus can be
/// re-scored offline **without changing app code** (plan §P0/Experiment A).
///
/// [widthFill]/[heightFill] generalise the single `targetFill` the shipped
/// fitter applies to both axes. [focusBbox] selects whether the fit zooms to
/// the occupied bounding box (what ships) or to the full grid.
class FitterVariant {
  const FitterVariant({
    required this.name,
    required this.widthFill,
    required this.heightFill,
    this.focusBbox = true,
    this.capToGrid = true,
    this.maxCell = 96.0,
    this.minPreferredCell = 26.0,
  });

  final String name;
  final double widthFill;
  final double heightFill;
  final bool focusBbox;
  final bool capToGrid;
  final double maxCell;
  final double minPreferredCell;

  /// Pre-P1 behaviour: a single 0.80 fill on both axes, bbox-focused,
  /// grid-capped. Retained as the "before" column of the sweep.
  static const FitterVariant current = FitterVariant(
    name: 'legacy-0.80/0.80',
    widthFill: kLegacyBoardFill,
    heightFill: kLegacyBoardFill,
  );

  /// What ships after P1 — mirrors `kBoardWidthFill` / `kBoardHeightFill`.
  static const FitterVariant perAxis = FitterVariant(
    name: 'shipped-perAxis',
    widthFill: kBoardWidthFill,
    heightFill: kBoardHeightFill,
  );

  /// Per-axis fill, fitted to the full grid rather than the occupied bbox.
  static const FitterVariant gridFocused = FitterVariant(
    name: 'grid-focused',
    widthFill: kBoardWidthFill,
    heightFill: kBoardHeightFill,
    focusBbox: false,
  );

  /// Bbox-focused with the grid cap released (upper bound; sparse boards spill).
  static const FitterVariant bboxUncapped = FitterVariant(
    name: 'bbox-uncapped',
    widthFill: kBoardWidthFill,
    heightFill: kBoardHeightFill,
    capToGrid: false,
  );

  static const List<FitterVariant> sweep = [
    current,
    perAxis,
    gridFocused,
    bboxUncapped,
  ];
}

/// Replicates `BoardLayoutMetrics.fitCellSizeForBoundsCappedToGrid` with
/// per-axis fills. Kept local to the harness so Experiment A can run before
/// (and independently of) any app change; [FitterVariant.current] reproduces
/// the shipped result exactly.
double fitCellPx({
  required ReferenceDevice device,
  required FitterVariant variant,
  required int bboxWidth,
  required int bboxHeight,
  required int gridWidth,
  required int gridHeight,
}) {
  final bandW = device.bandW;
  final bandH = device.bandH;
  if (bandW <= 0 || bandH <= 0) return 0;

  final fitW = variant.focusBbox ? bboxWidth : gridWidth;
  final fitH = variant.focusBbox ? bboxHeight : gridHeight;
  if (fitW <= 0 || fitH <= 0) return 0;

  final targetW = bandW * variant.widthFill;
  final targetH = bandH * variant.heightFill;

  var s = min(targetW / fitW, targetH / fitH);
  s = min(s, variant.maxCell);

  final atMinFits = variant.minPreferredCell * fitW <= targetW &&
      variant.minPreferredCell * fitH <= targetH;
  if (atMinFits) {
    s = max(s, variant.minPreferredCell);
    s = min(s, variant.maxCell);
  }

  if (variant.capToGrid && gridWidth > 0 && gridHeight > 0) {
    final gridCap = min(bandW / gridWidth, bandH / gridHeight);
    if (gridCap > 0) s = min(s, gridCap);
  }
  return s;
}

/// Composition / dead-space structure of one board's occupied cells.
class CompositionMetrics {
  const CompositionMetrics({
    required this.largestEmptyRowRun,
    required this.largestEmptyColRun,
    required this.largestEmptyRegion,
    required this.isolatedNodeCount,
    required this.meanLocalDensity,
  });

  /// Longest run of consecutive grid rows containing no node.
  final int largestEmptyRowRun;

  /// Longest run of consecutive grid columns containing no node.
  final int largestEmptyColRun;

  /// Largest 4-connected component of empty cells inside the grid.
  final int largestEmptyRegion;

  /// Nodes with no orthogonally adjacent node.
  final int isolatedNodeCount;

  /// Mean over nodes of (occupied 8-neighbours / 8) — how clustered the board
  /// reads locally, independent of overall grid size.
  final double meanLocalDensity;

  static CompositionMetrics compute(LevelData level) {
    final w = level.gridWidth;
    final h = level.gridHeight;
    if (w <= 0 || h <= 0 || level.nodes.isEmpty) {
      return const CompositionMetrics(
        largestEmptyRowRun: 0,
        largestEmptyColRun: 0,
        largestEmptyRegion: 0,
        isolatedNodeCount: 0,
        meanLocalDensity: 0,
      );
    }
    final occupied = <int>{for (final n in level.nodes) n.y * w + n.x};
    bool at(int x, int y) =>
        x >= 0 && y >= 0 && x < w && y < h && occupied.contains(y * w + x);

    // Empty row / column runs.
    var rowRun = 0, bestRowRun = 0;
    for (var y = 0; y < h; y++) {
      var empty = true;
      for (var x = 0; x < w && empty; x++) {
        if (at(x, y)) empty = false;
      }
      rowRun = empty ? rowRun + 1 : 0;
      bestRowRun = max(bestRowRun, rowRun);
    }
    var colRun = 0, bestColRun = 0;
    for (var x = 0; x < w; x++) {
      var empty = true;
      for (var y = 0; y < h && empty; y++) {
        if (at(x, y)) empty = false;
      }
      colRun = empty ? colRun + 1 : 0;
      bestColRun = max(bestColRun, colRun);
    }

    // Largest 4-connected empty region (flood fill).
    final seen = <int>{};
    var bestRegion = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final key = y * w + x;
        if (occupied.contains(key) || seen.contains(key)) continue;
        var size = 0;
        final stack = <int>[key];
        seen.add(key);
        while (stack.isNotEmpty) {
          final k = stack.removeLast();
          size++;
          final kx = k % w;
          final ky = k ~/ w;
          for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
            final nx = kx + dx;
            final ny = ky + dy;
            if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
            final nk = ny * w + nx;
            if (occupied.contains(nk) || seen.contains(nk)) continue;
            seen.add(nk);
            stack.add(nk);
          }
        }
        bestRegion = max(bestRegion, size);
      }
    }

    // Isolation + local density.
    var isolated = 0;
    var densitySum = 0.0;
    for (final n in level.nodes) {
      var ortho = 0;
      var around = 0;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          if (!at(n.x + dx, n.y + dy)) continue;
          around++;
          if (dx == 0 || dy == 0) ortho++;
        }
      }
      if (ortho == 0) isolated++;
      densitySum += around / 8.0;
    }

    return CompositionMetrics(
      largestEmptyRowRun: bestRowRun,
      largestEmptyColRun: bestColRun,
      largestEmptyRegion: bestRegion,
      isolatedNodeCount: isolated,
      meanLocalDensity: densitySum / level.nodes.length,
    );
  }
}

/// Production per-candidate time budget (what the app actually ships).
const Duration kProdBudget = Duration(milliseconds: 200);

/// Deterministic sample of [count] distinct ids in `[minId, maxId]`.
List<int> sampleLevelIds({
  required int count,
  required int minId,
  required int maxId,
  required int seed,
}) {
  final rng = Random(seed);
  final span = maxId - minId + 1;
  final ids = <int>{};
  while (ids.length < count) {
    ids.add(minId + rng.nextInt(span));
  }
  return ids.toList()..sort();
}

/// One fully-measured board.
class BoardRow {
  BoardRow({
    required this.label,
    required this.levelId,
    required this.sector,
    required this.worldName,
    required this.gridW,
    required this.gridH,
    required this.maskCells,
    required this.bboxW,
    required this.bboxH,
    required this.metrics,
    required this.topo,
    required this.cores,
    required this.locks,
    required this.relays,
    required this.phases,
    required this.portals,
    required this.directive,
    required this.timeLimitSec,
    required this.inBand,
    required this.genMs,
    required this.cellPx,
    required this.composition,
    required this.bboxWidthCells,
    required this.bboxHeightCells,
  });

  final String label; // "L742" or "20260813"
  final int levelId;
  final int sector;
  final String worldName;
  final int gridW;
  final int gridH;

  /// Cells allowed by the silhouette mask, or `gridW*gridH` when unmasked.
  final int maskCells;
  final int bboxW;
  final int bboxH;

  final LevelMetrics metrics;
  final LevelTopologyMetrics topo;

  final int cores;
  final int locks;
  final int relays;
  final int phases;
  final int portals;

  final String directive;
  final int timeLimitSec;
  final bool inBand;
  final int genMs;

  /// Rendered cell edge in logical px on the reference screen.
  final double cellPx;

  /// Dead-space structure and clustering of the occupied cells.
  final CompositionMetrics composition;

  /// Padded occupied bounds the fitter actually sees (`OccupiedBounds`, pad 1).
  final int bboxWidthCells;
  final int bboxHeightCells;

  int get nodes => metrics.nodeCount;
  int get gridCells => gridW * gridH;
  int get bboxCells => bboxW * bboxH;

  /// Share of the **fixed 8×8 canvas** with no node on it.
  double get canvasEmptyPct => 100 * (1 - nodes / kCanvasCells);

  /// Share of this level's own grid with no node on it.
  double get gridEmptyPct => 100 * (1 - nodes / gridCells);

  /// Share of the node bounding box with no node on it (interior holes).
  double get bboxEmptyPct => 100 * (1 - nodes / bboxCells);

  /// Share of the fixed canvas the grid does not even span (dead border).
  double get canvasUnusedByGridPct => 100 * (1 - gridCells / kCanvasCells);

  bool get hasMask => maskCells != gridCells;

  bool get oversize => gridCells > kCanvasCells;

  // ── pixel space, reference screen ────────────────────────────────────────

  /// Pixels covered by node cells.
  double get nodePx => nodes * cellPx * cellPx;

  /// Pixels covered by the whole rendered grid (nodes + holes).
  double get gridPx => gridCells * cellPx * cellPx;

  /// Share of the playfield band with no node on it — what the player
  /// actually perceives as empty space (board is scaled to fit the band).
  double get screenEmptyPct => 100 * (1 - nodePx / kBandArea);

  /// Share of the playfield band the rendered grid spans at all
  /// (100% − this = letterboxing around the board).
  double get boardCoveragePct => 100 * (gridPx / kBandArea);

  /// Interaction target edge in logical px. Since P2 the hit box is the full
  /// cell (`NodeComponent.containsLocalPoint`), decoupled from the painted
  /// sprite — which remains [kNodeVisualScale] of the cell and is reported as
  /// [spritePx] so the P2 delta stays visible.
  double get tapPx => cellPx;

  /// Painted tile edge in logical px — what the hit box used to be.
  double get spritePx => cellPx * kNodeVisualScale;

  /// Nodes per bounding-box cell — "how solid does the cluster read".
  double get bboxOccupancy => bboxCells == 0 ? 0 : nodes / bboxCells;

  // ── re-measurement under alternative devices / fitters ───────────────────

  /// Cell edge this board would render at on [device] under [variant].
  double cellPxFor(ReferenceDevice device, FitterVariant variant) => fitCellPx(
        device: device,
        variant: variant,
        bboxWidth: bboxWidthCells,
        bboxHeight: bboxHeightCells,
        gridWidth: gridW,
        gridHeight: gridH,
      );

  /// Share of [device]'s band the rendered grid spans under [variant].
  double boardCoverPctFor(ReferenceDevice device, FitterVariant variant) {
    final c = cellPxFor(device, variant);
    return 100 * (gridCells * c * c) / device.bandArea;
  }

  /// Share of [device]'s band with no node on it under [variant].
  double screenEmptyPctFor(ReferenceDevice device, FitterVariant variant) {
    final c = cellPxFor(device, variant);
    return 100 * (1 - (nodes * c * c) / device.bandArea);
  }
}

/// Measures one already-generated [level].
BoardRow measure(
  LevelData level, {
  required String label,
  required int levelId,
  required DifficultyProfile profile,
  required String directive,
  required int timeLimitSec,
  required int genMs,
  required int sector,
  required String worldName,
}) {
  final m = LevelMetrics.compute(level, includeViablePath: true);
  final topo = LevelTopologyMetrics.compute(level);

  var minX = 1 << 30, minY = 1 << 30, maxX = -1, maxY = -1;
  for (final n in level.nodes) {
    minX = min(minX, n.x);
    maxX = max(maxX, n.x);
    minY = min(minY, n.y);
    maxY = max(maxY, n.y);
  }
  final bboxW = level.nodes.isEmpty ? 0 : maxX - minX + 1;
  final bboxH = level.nodes.isEmpty ? 0 : maxY - minY + 1;

  final mask = level.playCells;
  final maskCells = (mask == null || mask.isEmpty)
      ? level.gridWidth * level.gridHeight
      : mask.length;

  // Same math ChainPopGame runs at layout time, on a reference phone screen.
  final bounds = OccupiedBounds.fromLevel(level, pad: 1);
  final cellPx = BoardLayoutMetrics.fitCellSizeForBoundsCappedToGrid(
    bandW: kBandW,
    bandH: kBandH,
    bboxWidth: bounds.bboxWidth,
    bboxHeight: bounds.bboxHeight,
    gridWidth: level.gridWidth,
    gridHeight: level.gridHeight,
    widthFill: kBoardWidthFill,
    heightFill: kBoardHeightFill,
  );

  return BoardRow(
    label: label,
    levelId: levelId,
    sector: sector,
    worldName: worldName,
    gridW: level.gridWidth,
    gridH: level.gridHeight,
    maskCells: maskCells,
    bboxW: bboxW,
    bboxH: bboxH,
    metrics: m,
    topo: topo,
    cores: level.nodes.where((n) => n.isCore).length,
    locks: level.nodes.where((n) => n.kind == NodeKind.locked).length,
    relays: level.nodes.where((n) => n.kind == NodeKind.relay).length,
    phases: level.nodes.map((n) => n.phaseGroup).fold<int>(0, max),
    portals: level.portalPairs.length,
    directive: directive,
    timeLimitSec: timeLimitSec,
    inBand: profile.passes(m),
    genMs: genMs,
    cellPx: cellPx,
    composition: CompositionMetrics.compute(level),
    bboxWidthCells: bounds.bboxWidth,
    bboxHeightCells: bounds.bboxHeight,
  );
}

/// Generates + measures a campaign batch.
List<BoardRow> runCampaignBatch({
  required List<int> levelIds,
  required DifficultyMode mode,
  required DifficultyProfile profile,
  required List<int> failures,
}) {
  final gen = LevelGenerator();
  final rows = <BoardRow>[];
  final sw = Stopwatch();
  for (final id in levelIds) {
    sw
      ..reset()
      ..start();
    final r = gen.generate(id, mode: mode, timeBudget: kProdBudget);
    sw.stop();
    if (!r.isSuccess) {
      failures.add(id);
      print('  L$id: GENERATION FAILED (${r.error})');
      continue;
    }
    final level = r.value;
    final world = worldForLevel(id);
    final row = measure(
      level,
      label: 'L$id',
      levelId: id,
      profile: profile,
      directive: directiveFor(levelId: id, mode: mode).label,
      timeLimitSec: computeGameTimeLimit(mode, level.nodes.length, id) ?? 0,
      genMs: sw.elapsedMilliseconds,
      sector: world.sector.mechanicBudgetTier,
      worldName: world.name,
    );
    rows.add(row);
    printRow(row);
  }
  return rows;
}

void printRow(BoardRow r) {
  final m = r.metrics;
  final tempo = m.tempoProfile;
  final tempoMin = tempo.isEmpty ? 0 : tempo.reduce(min);
  final tempoMax = tempo.isEmpty ? 0 : tempo.reduce(max);
  print(
    '  ${r.label.padRight(9)} '
    'S${r.sector} ${r.gridW}x${r.gridH} nodes=${r.nodes.toString().padLeft(2)} '
    '| EMPTY screen=${_p(r.screenEmptyPct)} canvas=${_p(r.canvasEmptyPct)} '
    'grid=${_p(r.gridEmptyPct)} '
    'bbox=${r.bboxW}x${r.bboxH}/${_p(r.bboxEmptyPct)} '
    'cover=${_p(r.boardCoveragePct)} cell=${r.cellPx.toStringAsFixed(0)}px '
    'tap=${r.tapPx.toStringAsFixed(0)}px '
    'mask=${r.hasMask ? r.maskCells.toString() : "-"}'
    '${r.oversize ? " OVERSIZE" : ""} '
    '| COMP occ=${(r.bboxOccupancy * 100).toStringAsFixed(0)}% '
    'emptyRun=${r.composition.largestEmptyRowRun}r/'
    '${r.composition.largestEmptyColRun}c '
    'emptyRegion=${r.composition.largestEmptyRegion} '
    'iso=${r.composition.isolatedNodeCount} '
    'localDens=${r.composition.meanLocalDensity.toStringAsFixed(2)} '
    '| open=${m.firstLegalMoveCount.toString().padLeft(2)} '
    'w0=${m.waveZeroWidth.toString().padLeft(2)} '
    'waves=${m.waveDepth.toString().padLeft(2)} '
    'CUD=${m.criticalUnlockDepth.toString().padLeft(2)} '
    'FSR=${_p(m.forcedSequenceRatio * 100)} '
    'BF=${m.averageBranchingFactor.toStringAsFixed(1).padLeft(4)} '
    'tempo=$tempoMin-$tempoMax var=${m.frontierVariance.toStringAsFixed(1)} '
    'paths=${m.viablePathCount}${m.viablePathCountCapped ? "+" : ""} '
    'effort=${m.searchEffortScore} '
    '| chokes=${m.chokePointCount} hub=${m.maxHubInDegree} '
    'antichain=${m.maxAntichainWidth} chainMax=${r.topo.chainDepthMax} '
    'fanout=${r.topo.avgUnlockFanout.toStringAsFixed(1)} '
    '| cores=${r.cores} lock=${r.locks} relay=${r.relays} '
    'phase=${r.phases} portal=${r.portals} '
    '| ${r.directive} t=${r.timeLimitSec}s inBand=${r.inBand ? "Y" : "n"} '
    'gen=${r.genMs}ms',
  );
}

String _p(double v) => '${v.toStringAsFixed(0)}%';

// ── aggregates ─────────────────────────────────────────────────────────────

class _Stat {
  _Stat(this.name, this.values);
  final String name;
  final List<double> values;

  double get mean =>
      values.isEmpty ? 0 : values.reduce((a, b) => a + b) / values.length;
  double _q(double f) {
    if (values.isEmpty) return 0;
    final s = List<double>.from(values)..sort();
    final i = ((s.length - 1) * f).round();
    return s[i];
  }

  double get p0 => _q(0);
  double get p25 => _q(0.25);
  double get p50 => _q(0.5);
  double get p75 => _q(0.75);
  double get p95 => _q(0.95);
  double get p100 => _q(1);
}

void printSummary(String label, List<BoardRow> rows, List<int> failures) {
  print('\n===== SUMMARY — $label (n=${rows.length}, '
      'failures=${failures.length}${failures.isEmpty ? "" : " ${failures.join(",")}"}) =====');
  if (rows.isEmpty) return;

  final stats = <_Stat>[
    _Stat('nodes', [for (final r in rows) r.nodes.toDouble()]),
    _Stat('screenEmpty%', [for (final r in rows) r.screenEmptyPct]),
    _Stat('boardCover%', [for (final r in rows) r.boardCoveragePct]),
    _Stat('cellPx', [for (final r in rows) r.cellPx]),
    _Stat('tapPx', [for (final r in rows) r.tapPx]),
    _Stat('spritePx', [for (final r in rows) r.spritePx]),
    _Stat('bboxOccupancy', [for (final r in rows) r.bboxOccupancy]),
    _Stat('emptyRowRun', [
      for (final r in rows) r.composition.largestEmptyRowRun.toDouble()
    ]),
    _Stat('emptyColRun', [
      for (final r in rows) r.composition.largestEmptyColRun.toDouble()
    ]),
    _Stat('emptyRegion', [
      for (final r in rows) r.composition.largestEmptyRegion.toDouble()
    ]),
    _Stat('isolatedNodes', [
      for (final r in rows) r.composition.isolatedNodeCount.toDouble()
    ]),
    _Stat('meanLocalDens', [
      for (final r in rows) r.composition.meanLocalDensity
    ]),
    _Stat('canvasEmpty%', [for (final r in rows) r.canvasEmptyPct]),
    _Stat('gridEmpty%', [for (final r in rows) r.gridEmptyPct]),
    _Stat('bboxEmpty%', [for (final r in rows) r.bboxEmptyPct]),
    _Stat('gridCells', [for (final r in rows) r.gridCells.toDouble()]),
    _Stat('opening', [
      for (final r in rows) r.metrics.firstLegalMoveCount.toDouble()
    ]),
    _Stat('waveZero', [for (final r in rows) r.metrics.waveZeroWidth.toDouble()]),
    _Stat('waves', [for (final r in rows) r.metrics.waveDepth.toDouble()]),
    _Stat('CUD', [
      for (final r in rows) r.metrics.criticalUnlockDepth.toDouble()
    ]),
    _Stat('FSR%', [
      for (final r in rows) r.metrics.forcedSequenceRatio * 100
    ]),
    _Stat('BF', [for (final r in rows) r.metrics.averageBranchingFactor]),
    _Stat('frontierVar', [for (final r in rows) r.metrics.frontierVariance]),
    _Stat('effort', [
      for (final r in rows) r.metrics.searchEffortScore.toDouble()
    ]),
    _Stat('chokes', [
      for (final r in rows) r.metrics.chokePointCount.toDouble()
    ]),
    _Stat('maxHub', [for (final r in rows) r.metrics.maxHubInDegree.toDouble()]),
    _Stat('antichain', [
      for (final r in rows) r.metrics.maxAntichainWidth.toDouble()
    ]),
    _Stat('timeLimitSec', [for (final r in rows) r.timeLimitSec.toDouble()]),
    _Stat('genMs', [for (final r in rows) r.genMs.toDouble()]),
  ];

  print('  ${"metric".padRight(14)}${"min".padLeft(8)}${"p25".padLeft(8)}'
      '${"median".padLeft(8)}${"p75".padLeft(8)}${"p95".padLeft(8)}'
      '${"max".padLeft(8)}${"mean".padLeft(8)}');
  for (final s in stats) {
    print('  ${s.name.padRight(14)}'
        '${s.p0.toStringAsFixed(1).padLeft(8)}'
        '${s.p25.toStringAsFixed(1).padLeft(8)}'
        '${s.p50.toStringAsFixed(1).padLeft(8)}'
        '${s.p75.toStringAsFixed(1).padLeft(8)}'
        '${s.p95.toStringAsFixed(1).padLeft(8)}'
        '${s.p100.toStringAsFixed(1).padLeft(8)}'
        '${s.mean.toStringAsFixed(1).padLeft(8)}');
  }

  final inBand = rows.where((r) => r.inBand).length;
  print('\n  in-band: $inBand/${rows.length} '
      '(${(100 * inBand / rows.length).toStringAsFixed(0)}%)');

  // Mechanic presence.
  int has(bool Function(BoardRow) f) => rows.where(f).length;
  print('  mechanics: cores=${has((r) => r.cores > 0)} '
      'locked=${has((r) => r.locks > 0)} relay=${has((r) => r.relays > 0)} '
      'phase=${has((r) => r.phases > 0)} portal=${has((r) => r.portals > 0)} '
      'mask=${has((r) => r.hasMask)} '
      '(levels out of ${rows.length})');

  _histCount('grid sizes', {
    for (final r in rows) '${r.gridW}x${r.gridH}': 0,
  }, rows, (r) => '${r.gridW}x${r.gridH}');
  _histCount('directives', {}, rows, (r) => r.directive);
  _histBucket('opening width', rows,
      (r) => r.metrics.firstLegalMoveCount.toDouble(), [3, 5, 7, 9, 11, 14]);
  _histBucket('node count', rows, (r) => r.nodes.toDouble(),
      [10, 15, 20, 25, 30, 35, 40]);
  _histBucket('screen empty %', rows, (r) => r.screenEmptyPct,
      [70, 75, 80, 85, 90, 95]);
  _histBucket('board cover %', rows, (r) => r.boardCoveragePct,
      [40, 50, 60, 70, 80, 90]);
  _histBucket('canvas empty %', rows, (r) => r.canvasEmptyPct,
      [30, 40, 50, 60, 70, 80]);
  _histBucket('grid empty %', rows, (r) => r.gridEmptyPct,
      [20, 30, 40, 50, 60, 70]);
  _histBucket(
      'FSR %', rows, (r) => r.metrics.forcedSequenceRatio * 100, [30, 40, 50, 60, 70]);

  final slow = List<BoardRow>.from(rows)
    ..sort((a, b) => b.genMs.compareTo(a.genMs));
  print('  slowest: ${slow.take(5).map((r) => "${r.label}=${r.genMs}ms").join(", ")}');
  print('');
}

/// **Experiment A** — re-scores [rows] under every [FitterVariant] on every
/// [ReferenceDevice], with no app change. Answers: how much of the emptiness
/// is layout, and how much is left for board geometry to close.
void printFitterSweep(String label, List<BoardRow> rows) {
  if (rows.isEmpty) return;
  print('\n===== FITTER SWEEP — $label (n=${rows.length}) =====');
  print('  ${"device".padRight(10)}${"variant".padRight(24)}'
      '${"cell p50".padLeft(10)}${"cell min".padLeft(10)}'
      '${"tap p50".padLeft(10)}${"tap>=44".padLeft(10)}'
      '${"cover p50".padLeft(11)}${"cover min".padLeft(11)}'
      '${"cover>=55".padLeft(11)}${"empty p50".padLeft(11)}');
  for (final device in ReferenceDevice.all) {
    for (final variant in FitterVariant.sweep) {
      final cells = [for (final r in rows) r.cellPxFor(device, variant)];
      final covers = [
        for (final r in rows) r.boardCoverPctFor(device, variant)
      ];
      final empties = [
        for (final r in rows) r.screenEmptyPctFor(device, variant)
      ];
      // Post-P2 the hit box is the full cell; that is what these tap numbers
      // measure, so the sweep reports the ceiling the layout makes reachable.
      final tapOk = cells.where((c) => c >= 44.0).length;
      final coverOk = covers.where((c) => c >= 55.0).length;
      print('  ${device.name.padRight(10)}${variant.name.padRight(24)}'
          '${_med(cells).toStringAsFixed(1).padLeft(10)}'
          '${cells.reduce(min).toStringAsFixed(1).padLeft(10)}'
          '${_med(cells).toStringAsFixed(1).padLeft(10)}'
          '${"$tapOk/${rows.length}".padLeft(10)}'
          '${_med(covers).toStringAsFixed(1).padLeft(11)}'
          '${covers.reduce(min).toStringAsFixed(1).padLeft(11)}'
          '${"$coverOk/${rows.length}".padLeft(11)}'
          '${_med(empties).toStringAsFixed(1).padLeft(11)}');
    }
  }
  print('');
}

double _med(List<double> v) {
  if (v.isEmpty) return 0;
  final s = List<double>.from(v)..sort();
  return s[(s.length - 1) ~/ 2];
}

void _histCount(
  String title,
  Map<String, int> seed,
  List<BoardRow> rows,
  String Function(BoardRow) key,
) {
  final counts = Map<String, int>.from(seed);
  for (final r in rows) {
    counts[key(r)] = (counts[key(r)] ?? 0) + 1;
  }
  final entries = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  print('  $title: ${entries.map((e) => "${e.key}=${e.value}").join("  ")}');
}

void _histBucket(
  String title,
  List<BoardRow> rows,
  double Function(BoardRow) value,
  List<double> edges,
) {
  final labels = <String>[];
  final counts = <int>[];
  for (var i = 0; i <= edges.length; i++) {
    final lo = i == 0 ? null : edges[i - 1];
    final hi = i == edges.length ? null : edges[i];
    labels.add(lo == null
        ? '<${_n(hi!)}'
        : hi == null
            ? '>=${_n(lo)}'
            : '${_n(lo)}-${_n(hi)}');
    counts.add(0);
  }
  for (final r in rows) {
    final v = value(r);
    var idx = edges.length;
    for (var i = 0; i < edges.length; i++) {
      if (v < edges[i]) {
        idx = i;
        break;
      }
    }
    counts[idx]++;
  }
  final parts = <String>[];
  for (var i = 0; i < labels.length; i++) {
    if (counts[i] == 0) continue;
    parts.add('${labels[i]}:${counts[i]}');
  }
  print('  $title: ${parts.join("  ")}');
}

String _n(double v) => v == v.roundToDouble() ? v.toInt().toString() : '$v';

/// Writes a CSV of every measured board for offline slicing.
void writeCsv(String path, List<BoardRow> rows) {
  final f = File(path);
  f.parent.createSync(recursive: true);
  final b = StringBuffer()
    ..writeln('label,levelId,sector,world,gridW,gridH,gridCells,maskCells,'
        'nodes,screenEmptyPct,boardCoverPct,cellPx,tapPx,spritePx,'
        'canvasEmptyPct,gridEmptyPct,bboxW,bboxH,bboxEmptyPct,bboxOccupancy,'
        'emptyRowRun,emptyColRun,emptyRegion,isolatedNodes,meanLocalDensity,'
        'opening,waveZero,waves,cud,fsrPct,bf,frontierVar,paths,pathsCapped,'
        'effort,chokes,maxHub,antichain,chainDepthMax,avgFanout,'
        'cores,locks,relays,phases,portals,directive,timeLimitSec,inBand,genMs');
  for (final r in rows) {
    final m = r.metrics;
    b.writeln([
      r.label,
      r.levelId,
      r.sector,
      '"${r.worldName}"',
      r.gridW,
      r.gridH,
      r.gridCells,
      r.maskCells,
      r.nodes,
      r.screenEmptyPct.toStringAsFixed(1),
      r.boardCoveragePct.toStringAsFixed(1),
      r.cellPx.toStringAsFixed(1),
      r.tapPx.toStringAsFixed(1),
      r.spritePx.toStringAsFixed(1),
      r.canvasEmptyPct.toStringAsFixed(1),
      r.gridEmptyPct.toStringAsFixed(1),
      r.bboxW,
      r.bboxH,
      r.bboxEmptyPct.toStringAsFixed(1),
      r.bboxOccupancy.toStringAsFixed(3),
      r.composition.largestEmptyRowRun,
      r.composition.largestEmptyColRun,
      r.composition.largestEmptyRegion,
      r.composition.isolatedNodeCount,
      r.composition.meanLocalDensity.toStringAsFixed(3),
      m.firstLegalMoveCount,
      m.waveZeroWidth,
      m.waveDepth,
      m.criticalUnlockDepth,
      (m.forcedSequenceRatio * 100).toStringAsFixed(1),
      m.averageBranchingFactor.toStringAsFixed(2),
      m.frontierVariance.toStringAsFixed(2),
      m.viablePathCount,
      m.viablePathCountCapped,
      m.searchEffortScore,
      m.chokePointCount,
      m.maxHubInDegree,
      m.maxAntichainWidth,
      r.topo.chainDepthMax,
      r.topo.avgUnlockFanout.toStringAsFixed(2),
      r.cores,
      r.locks,
      r.relays,
      r.phases,
      r.portals,
      r.directive,
      r.timeLimitSec,
      r.inBand,
      r.genMs,
    ].join(','));
  }
  f.writeAsStringSync(b.toString());
  print('  CSV: $path');
}
