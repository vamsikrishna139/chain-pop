// T0.4 — statistics, hashes and the post-P1 classification for the frozen
// adversarial corpus.
//
// The corpus **evaluates**; it never tunes (T0.4§g). Nothing in this file may
// grow an assertion that a generator change is expected to satisfy: the moment
// thresholds are chosen after looking at frozen ids, the instrument becomes an
// optimiser and the result is void. The only asserting file in T0.4 is
// `adversarial_corpus_guards_test.dart`, and it asserts *invariance*, never
// quality.
//
// ignore_for_file: avoid_print

import 'dart:io';

import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/difficulty_profile.dart';
import 'package:chain_pop/game/levels/generation/generation_error.dart';
import 'package:chain_pop/game/levels/generation/level_enrichment.dart';
import 'package:chain_pop/game/levels/generation/level_generator.dart';
import 'package:chain_pop/game/levels/level.dart';
import 'package:chain_pop/game/levels/level_directive.dart';
import 'package:chain_pop/game/levels/generation/result.dart';
import 'package:chain_pop/game/levels/level_solver.dart';
import 'package:chain_pop/game/world_registry.dart';
import 'package:chain_pop/screens/game/game_time_limit.dart';

import 'adversarial_corpus.dart';
import 'board_report_utils.dart';
import 'core_depth_ceiling.dart';
import 'corpus_version.dart';

// ─── Identity hashes ────────────────────────────────────────────────────────

/// FNV-1a 64, hex. Same construction `corpus_identity.dart` uses.
String fnv1a64(String s) {
  var h = 0xcbf29ce484222325;
  for (final byte in s.codeUnits) {
    h ^= byte;
    h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }
  return h.toRadixString(16);
}

/// **Guard 1 — geometry identity.** Grid, silhouette mask and every node's
/// `(id, x, y, dir)`.
///
/// `isCore` is explicitly exempt: the contract being asserted is "P1 changed
/// core selection, not puzzle geometry" (§0.1).
///
/// `kind` and `phaseGroup` are exempt too, and that exemption is **not**
/// cosmetic. `_markSpecialNodes` filters lock candidates on `!n.isCore` and
/// relay candidates on `!coreRows.contains(n.y)` (`level_enrichment.dart`), so
/// moving a core legitimately moves a lock or a relay. Hashing `kind` here
/// would turn an intended consequence of P1 into a red guard. Lock and relay
/// movement is instead **reported** through [mechanicHash], where it is visible
/// without being fatal.
String geometryHashOf(LevelData level) {
  final mask = level.playCells;
  final cells =
      (mask == null || mask.isEmpty) ? '-' : (mask.toList()..sort()).join('|');
  final b = StringBuffer()
    ..writeln('${level.gridWidth}x${level.gridHeight}')
    ..writeln(cells);
  for (final n in level.nodes) {
    b.writeln('${n.id},${n.x},${n.y},${n.dir.name}');
  }
  for (final p in level.portalPairs) {
    b.writeln('P${p.x1},${p.y1},${p.x2},${p.y2}');
  }
  return fnv1a64(b.toString());
}

/// **Guard 2 — solution-structure identity.** `LevelSolver.nodeWaveIndices`
/// over the board with every mechanic stripped.
///
/// The plan called for `hash(nodeWaveIndices)` on the shipped board, describing
/// it as "canonical, deterministic and core-independent". The first two hold;
/// the third does not. `_canRemoveWithSet` short-circuits on
/// `kind == NodeKind.locked` and on `phaseGroup > 0`, and lock placement is a
/// function of the core set — so wave indices on the *enriched* board move
/// whenever a lock moves, which P1 is allowed to do.
///
/// Stripping `kind` and `phaseGroup` restores the property the guard was meant
/// to have: this hash is a pure function of geometry, so it is genuinely
/// invariant across P1 and a change in it means the removal structure of the
/// puzzle itself moved. The enriched-board version is recorded separately as
/// [enrichedSolutionHash] — reported, not gated.
String solutionHashOf(LevelData level) {
  final bare = LevelData(
    levelId: level.levelId,
    gridWidth: level.gridWidth,
    gridHeight: level.gridHeight,
    playCells: level.playCells,
    portalPairs: level.portalPairs,
    nodes: [
      for (final n in level.nodes)
        n.copyWith(kind: NodeKind.normal, phaseGroup: 0, isCore: false),
    ],
  );
  return _waveHash(bare);
}

/// Wave indices on the board **as shipped**, mechanics included.
///
/// Reported, never gated. It is expected to move on any board where P1 relocates
/// a lock, a relay or a phase chunk; a diff here with [geometryHashOf] and
/// [solutionHashOf] both stable is the signature of exactly that, and is
/// benign.
String enrichedSolutionHash(LevelData level) => _waveHash(level);

/// The mechanic layer alone: `kind` and `phaseGroup` per node, plus `isCore`.
/// Reported. This is the column that makes "cores moved" a machine-readable
/// fact rather than an inference, and §e's classification reads it.
String mechanicHash(LevelData level) {
  final b = StringBuffer();
  for (final n in level.nodes) {
    b.writeln('${n.id},${n.isCore},${n.kind.name},${n.phaseGroup}');
  }
  return fnv1a64(b.toString());
}

/// Core ids alone — the narrowest "did core selection change?" signal.
String coreSetHash(LevelData level) => fnv1a64(
      (level.nodes.where((n) => n.isCore).map((n) => n.id).toList()..sort())
          .join(','),
    );

String _waveHash(LevelData level) {
  final waves = LevelSolver.nodeWaveIndices(level);
  final ids = waves.keys.toList()..sort();
  final b = StringBuffer();
  for (final id in ids) {
    b.writeln('$id:${waves[id]}');
  }
  // Unreachable nodes are absent from the map; recording the count makes a
  // board that became unsolvable a hash change rather than a silent shrink.
  b.writeln('reached=${waves.length}/${level.nodes.length}');
  return fnv1a64(b.toString());
}

// ─── Mode floors ────────────────────────────────────────────────────────────

/// The `tapsToWin` floor each mode is held to, from T0.4§f's hard-gate row.
///
/// Medium and Hard: "min `tapsToWin` >= 6". Easy: "<=6-tap share = 0%", which
/// is the same statement written as a floor of 7. These are the thresholds
/// §e's classification and the `ceiling < floor` count read; they are P1's
/// acceptance gates, fixed here **before** any P1 code exists so they cannot be
/// retro-fitted to whatever P1 happens to produce.
const Map<DifficultyMode, int> kModeTapFloor = {
  DifficultyMode.easy: 7,
  DifficultyMode.medium: 6,
  DifficultyMode.hard: 6,
};

int tapFloorFor(DifficultyMode mode) => kModeTapFloor[mode] ?? 6;

// ─── Measured row ───────────────────────────────────────────────────────────

/// One frozen board, fully measured: everything `BoardRow` records plus the
/// corpus's own bookkeeping and the §d ceiling.
class AdversarialRow {
  AdversarialRow({
    required this.entry,
    required this.board,
    required this.ceiling,
    required this.geometryHash,
    required this.solutionHash,
    required this.enrichedSolutionHash,
    required this.mechanicHash,
    required this.coreSetHash,
    required this.corePath,
    required this.coreSelectionAttempts,
  });

  final CorpusEntry entry;
  final BoardRow board;
  final CoreDepthCeiling ceiling;

  final String geometryHash;
  final String solutionHash;
  final String enrichedSolutionHash;
  final String mechanicHash;
  final String coreSetHash;

  /// Which of `_climaxBandCoreIds`'s hatches produced the cores that shipped,
  /// or null on a coreless board (and on the vanishingly unlikely board whose
  /// emitted core set matches no recorded selection).
  ///
  /// T0.4's optional telemetry. T1.2 needs it to place its quality floor and
  /// T1.3's balance note asks for the relaxation rate before tuning further;
  /// without it both are designed blind to how often the hatches fire.
  final CoreSelectionPath? corePath;

  /// Core selections made across every *candidate* this level generated, not
  /// just the one that shipped. A proxy for how much the generator thrashed.
  final int coreSelectionAttempts;

  int get levelId => entry.levelId;
  DifficultyMode get mode => entry.mode;
  int get tapsToWin => board.tapsToWin;
  int get nodes => board.nodes;
  double get captureRate => ceiling.captureRate;

  /// The board cannot reach its mode's floor no matter which cores are chosen.
  bool get geometricallyUnfixable =>
      ceiling.ceilingTapDepth < tapFloorFor(mode);
}

/// Profile that pairs with [mode] — the same pairing the `report_*_100`
/// harnesses use, kept in one place so a corpus row and a report row are
/// scored identically.
DifficultyProfile profileFor(DifficultyMode mode) => switch (mode) {
      DifficultyMode.easy => DifficultyProfile.easy,
      DifficultyMode.medium => DifficultyProfile.medium,
      DifficultyMode.hard => DifficultyProfile.hard,
    };

/// Generates one frozen board and measures it completely.
///
/// **A fresh `LevelGenerator.neutral()` per board, deliberately.** This is not
/// a stylistic choice and the shared-instance version of it is a bug that was
/// caught during T0.4's first baseline run.
///
/// The T0.0a closure audit classifies `_diversityLedger` and
/// `_silhouetteSessionTracker` as *session state* — promoted into the contract,
/// not eliminated from it. A `LevelGenerator` reused across a batch therefore
/// emits boards that are a function of the **whole preceding sequence**, not of
/// `(levelId, mode, generationVersion)` alone. Measured: L1411/medium came out
/// with 17 nodes and `tapsToWin: 8` inside the 600-id ascending selection
/// sweep, and 18 nodes and `tapsToWin: 4` inside the 300-entry corpus sweep.
/// Same id, same mode, same code, different board.
///
/// T0.4§b freezes the corpus on `(levelId, mode, generationVersion)`. That key
/// is only well-defined if the board really is a function of it, so every
/// corpus generation starts from neutral session state. The cost is nil (a
/// `LevelGenerator` is cheap) and the alternative is a corpus whose rows change
/// when someone reorders the list.
///
/// The `report_*_100` harnesses keep their shared instance: they measure the
/// *sequence* a session actually produces, which is a different and equally
/// legitimate question. It is the reason a corpus row and a report row for the
/// same id can differ, and why they are not compared with each other.
///
/// `timeBudget: null` for the same reason the canary uses it — on the budgeted
/// path elapsed wall-clock decides control flow, so a budgeted corpus would
/// drift with machine load.
AdversarialRow measureEntry(CorpusEntry e) {
  final gen = LevelGenerator.neutral();
  // Inert in production; installed only for the duration of this one call so a
  // failure cannot leave a live sink behind for the rest of the suite.
  final selections = <CoreSelectionRecord>[];
  CoreSelectionTelemetry.sink = selections.add;
  final sw = Stopwatch()..start();
  final Result<LevelData, GenerationError> result;
  try {
    result = gen.generate(e.levelId, mode: e.mode, timeBudget: null);
  } finally {
    sw.stop();
    CoreSelectionTelemetry.sink = null;
  }
  if (!result.isSuccess) {
    throw StateError('corpus generation failed for ${e.key}: ${result.error}');
  }
  final level = result.value;

  // Match the shipped board's cores back to the selection that produced them.
  // `enrichLevel` runs once per candidate, so most of these records describe
  // levels that were never emitted; taking the last record would attribute the
  // wrong path on every board where the generator preferred an earlier
  // candidate. The last *matching* record is the right one — a later candidate
  // with an identical core set has, by definition, the same provenance.
  final shippedCores =
      (level.nodes.where((n) => n.isCore).map((n) => n.id).toList()..sort());
  CoreSelectionPath? corePath;
  for (final r in selections) {
    if (r.coreIds.length == shippedCores.length &&
        List.generate(r.coreIds.length, (i) => r.coreIds[i] == shippedCores[i])
            .every((x) => x)) {
      corePath = r.path;
    }
  }
  final world = worldForLevel(e.levelId);
  final board = measure(
    level,
    label: 'L${e.levelId}',
    levelId: e.levelId,
    mode: e.mode,
    profile: profileFor(e.mode),
    directive: directiveFor(levelId: e.levelId, mode: e.mode).label,
    timeLimitSec:
        computeGameTimeLimit(e.mode, level.nodes.length, e.levelId) ?? 0,
    genMs: sw.elapsedMilliseconds,
    sector: world.sector.mechanicBudgetTier,
    worldName: world.name,
  );
  return AdversarialRow(
    entry: e,
    board: board,
    ceiling: computeCoreDepthCeiling(level),
    geometryHash: geometryHashOf(level),
    solutionHash: solutionHashOf(level),
    enrichedSolutionHash: enrichedSolutionHash(level),
    mechanicHash: mechanicHash(level),
    coreSetHash: coreSetHash(level),
    corePath: shippedCores.isEmpty ? null : corePath,
    coreSelectionAttempts: selections.length,
  );
}

/// Generates and measures every entry in [entries].
///
/// Order-independent by construction — see [measureEntry].
List<AdversarialRow> measureCorpus(
  List<CorpusEntry> entries, {
  void Function(int done, int total)? onProgress,
}) {
  final rows = <AdversarialRow>[];
  for (final e in entries) {
    rows.add(measureEntry(e));
    onProgress?.call(rows.length, entries.length);
  }
  return rows;
}

// ─── CSV ────────────────────────────────────────────────────────────────────

/// Corpus bookkeeping columns, prepended to every board block.
const String _kCorpusColumns = 'view,quintile,severityRank,'
    'tapsToWin,ceilingTapDepth,captureRate,headroom,belowFloor,unfixable,'
    'geometryHash,solutionHash,enrichedSolutionHash,mechanicHash,coreSetHash,'
    'corePath,coreSelectionAttempts';

/// Writes one view's baseline CSV.
///
/// Columns are the corpus bookkeeping above plus the full [kBoardCsvHeader]
/// block, so a baseline row is a superset of a `report_*_100` row and the two
/// can be sliced with the same tools.
void writeAdversarialCsv(String path, List<AdversarialRow> rows) {
  final f = File(path);
  f.parent.createSync(recursive: true);
  final b = StringBuffer()
    ..write(kCorpusVersionHeader)
    ..writeln('# adversarialCorpusVersion: $kAdversarialCorpusVersion')
    ..writeln('# poolSeed: $kAdversarialPoolSeed')
    ..writeln('# frozen: selection is final — see adversarial_corpus.dart')
    ..writeln('$_kCorpusColumns,$kBoardCsvHeader');
  for (final r in rows) {
    b.writeln([
      r.entry.view.name,
      r.entry.quintile,
      r.entry.severityRank,
      r.tapsToWin,
      r.ceiling.ceilingTapDepth,
      r.captureRate.toStringAsFixed(3),
      r.ceiling.headroom,
      r.tapsToWin < tapFloorFor(r.mode),
      r.geometricallyUnfixable,
      r.geometryHash,
      r.solutionHash,
      r.enrichedSolutionHash,
      r.mechanicHash,
      r.coreSetHash,
      r.corePath?.name ?? 'none',
      r.coreSelectionAttempts,
      boardCsvRow(r.board),
    ].join(','));
  }
  f.writeAsStringSync(b.toString());
  print('  CSV: $path  (${rows.length} boards)');
}

/// One row of a committed baseline CSV, read back for the guards and for the
/// post-P1 diff.
class BaselineRecord {
  BaselineRecord({
    required this.levelId,
    required this.mode,
    required this.view,
    required this.quintile,
    required this.severityRank,
    required this.tapsToWin,
    required this.nodes,
    required this.cores,
    required this.ceilingTapDepth,
    required this.captureRate,
    required this.geometryHash,
    required this.solutionHash,
    required this.coreSetHash,
    required this.contentIdentity,
  });

  final int levelId;
  final DifficultyMode mode;
  final String view;
  final int quintile;
  final int severityRank;
  final int tapsToWin;
  final int nodes;
  final int cores;
  final int ceilingTapDepth;
  final double captureRate;
  final String geometryHash;
  final String solutionHash;
  final String coreSetHash;
  final String contentIdentity;

  String get key => '$levelId/${mode.name}';
}

/// Reads a committed baseline CSV back into records, keyed by `levelId/mode`.
///
/// Column lookup is **by name**, never by index. A baseline read positionally
/// would silently mis-parse the day someone inserts a column into
/// [kBoardCsvHeader], and the guards would then compare the wrong fields while
/// reporting green — the worst possible failure for a file whose whole job is
/// to be trusted.
Map<String, BaselineRecord> readBaseline(String path) {
  final lines = File(path)
      .readAsLinesSync()
      .where((l) => l.trim().isNotEmpty && !l.startsWith('#'))
      .toList();
  if (lines.isEmpty) throw StateError('empty baseline: $path');
  final header = lines.first.split(',');
  int col(String name) {
    final i = header.indexOf(name);
    if (i < 0) throw StateError('baseline $path has no column "$name"');
    return i;
  }

  final iView = col('view');
  final iQuintile = col('quintile');
  final iRank = col('severityRank');
  final iTaps = col('tapsToWin');
  final iCeiling = col('ceilingTapDepth');
  final iCapture = col('captureRate');
  final iGeom = col('geometryHash');
  final iSol = col('solutionHash');
  final iCoreSet = col('coreSetHash');
  final iLevelId = col('levelId');
  final iIdentity = col('contentIdentity');
  final iNodes = col('nodes');
  final iCores = col('cores');

  final out = <String, BaselineRecord>{};
  for (final line in lines.skip(1)) {
    final f = line.split(',');
    // `contentIdentity` is `levelId/mode/vN/recipeId` — the mode is carried in
    // the row itself, so a record can never be attributed to the wrong mode.
    final identity = f[iIdentity];
    // Fields are split on bare commas. The `world` column is quoted and no
    // world name contains a comma today, but a baseline that silently shifted
    // by one column would compare the wrong fields while reporting green —
    // the worst possible failure for this file. `contentIdentity` begins with
    // the level id, so cross-checking it against the `levelId` column catches
    // any shift immediately.
    if (f.length != header.length) {
      throw StateError('$path: row has ${f.length} fields, header has '
          '${header.length} — a value contains a bare comma');
    }
    if (!identity.startsWith('${f[iLevelId]}/')) {
      throw StateError('$path: contentIdentity "$identity" does not match '
          'levelId "${f[iLevelId]}" — columns are misaligned');
    }
    final modeName = identity.split('/')[1];
    final mode = DifficultyMode.values.firstWhere((m) => m.name == modeName);
    final rec = BaselineRecord(
      levelId: int.parse(f[iLevelId]),
      mode: mode,
      view: f[iView],
      quintile: int.parse(f[iQuintile]),
      severityRank: int.parse(f[iRank]),
      tapsToWin: int.parse(f[iTaps]),
      nodes: int.parse(f[iNodes]),
      cores: int.parse(f[iCores]),
      ceilingTapDepth: int.parse(f[iCeiling]),
      captureRate: double.parse(f[iCapture]),
      geometryHash: f[iGeom],
      solutionHash: f[iSol],
      coreSetHash: f[iCoreSet],
      contentIdentity: identity,
    );
    out[rec.key] = rec;
  }
  return out;
}

// ─── Post-P1 classification (T0.4§e) ────────────────────────────────────────

/// Mutually exclusive outcomes for one board, evaluated as a decision tree over
/// the baseline→current deltas.
///
/// `Q1: 34 FIXED / 4 UNFIXABLE / 2 SELECTOR-FAILED` is a work order.
/// `p50 6 -> 10` is a rumour.
enum BoardOutcome {
  /// A hard invariant moved. The whole result is invalid, not just this board.
  violation,

  /// At or above the mode floor, and the core set changed. The intended fix.
  fixed,

  /// At or above the floor, but the cores are the same nodes as before — the
  /// board got there by luck or by some other change. Worth investigating
  /// before it is counted as a success.
  incidental,

  /// Below the floor, and no core selection on this geometry could have
  /// reached it. Needs an escape valve upstream in candidate rejection; T1.2's
  /// bounded repick cannot help.
  unfixable,

  /// Below the floor, but the selector captured >=90% of the depth the board
  /// actually had. The selector did its job; the board was the limit.
  selectorOptimalBoardLimited,

  /// Below the floor with depth left on the table. This is the real bug.
  selectorFailed,
}

/// `captureRate` above which a below-floor board is judged board-limited rather
/// than selector-limited. Fixed here, before P1 exists, so it cannot be moved
/// to reclassify an unwelcome result.
const double kBoardLimitedCaptureThreshold = 0.90;

/// Classifies one board's baseline→current transition. Pure; testable without
/// generating anything.
BoardOutcome classifyBoard({
  required BaselineRecord baseline,
  required int currentTapsToWin,
  required int currentNodes,
  required String currentGeometryHash,
  required String currentSolutionHash,
  required String currentCoreSetHash,
  required int currentCeilingTapDepth,
  required double currentCaptureRate,
  required DifficultyMode mode,
}) {
  if (currentGeometryHash != baseline.geometryHash ||
      currentSolutionHash != baseline.solutionHash ||
      currentNodes != baseline.nodes) {
    return BoardOutcome.violation;
  }
  final floor = tapFloorFor(mode);
  if (currentTapsToWin >= floor) {
    return currentCoreSetHash != baseline.coreSetHash
        ? BoardOutcome.fixed
        : BoardOutcome.incidental;
  }
  if (currentCeilingTapDepth < floor) return BoardOutcome.unfixable;
  return currentCaptureRate >= kBoardLimitedCaptureThreshold
      ? BoardOutcome.selectorOptimalBoardLimited
      : BoardOutcome.selectorFailed;
}

// ─── Statistics ─────────────────────────────────────────────────────────────

/// Nearest-rank percentile, the same convention `printSummary` and the T0.3
/// canary use, so a corpus number can be read straight off a report summary.
int percentileInt(List<int> values, double f) {
  if (values.isEmpty) return 0;
  final s = List<int>.from(values)..sort();
  return s[((s.length - 1) * f).round()];
}

double percentileDouble(List<double> values, double f) {
  if (values.isEmpty) return 0;
  final s = List<double>.from(values)..sort();
  return s[((s.length - 1) * f).round()];
}

String _pct(double v) => '${(v * 100).toStringAsFixed(1)}%';

/// Prints the distribution table for one view.
void printViewSummary(String label, List<AdversarialRow> rows) {
  if (rows.isEmpty) return;
  final mode = rows.first.mode;
  final floor = tapFloorFor(mode);
  final taps = [for (final r in rows) r.tapsToWin];
  final nodes = [for (final r in rows) r.nodes];
  final capture = [for (final r in rows) r.captureRate];
  final unfixable = rows.where((r) => r.geometricallyUnfixable).length;
  final belowFloor = rows.where((r) => r.tapsToWin < floor).length;

  print('\n===== $label  (n=${rows.length}, ${mode.name}, floor=$floor) =====');
  print('  tapsToWin      min=${percentileInt(taps, 0)}  '
      'p25=${percentileInt(taps, 0.25)}  '
      'p50=${percentileInt(taps, 0.5)}  '
      'p75=${percentileInt(taps, 0.75)}  '
      'p95=${percentileInt(taps, 0.95)}  '
      'max=${percentileInt(taps, 1)}');
  print('  nodes          min=${percentileInt(nodes, 0)}  '
      'p50=${percentileInt(nodes, 0.5)}  '
      'max=${percentileInt(nodes, 1)}   '
      '<-- node-count equality guard watches this');
  print(
      '  captureRate    p25=${percentileDouble(capture, 0.25).toStringAsFixed(2)}  '
      'p50=${percentileDouble(capture, 0.5).toStringAsFixed(2)}  '
      'p75=${percentileDouble(capture, 0.75).toStringAsFixed(2)}');
  print('  <=6 taps       ${rows.where((r) => r.tapsToWin <= 6).length}'
      '/${rows.length} = '
      '${_pct(rows.where((r) => r.tapsToWin <= 6).length / rows.length)}');
  print('  below floor    $belowFloor/${rows.length}');
  print('  UNFIXABLE      $unfixable/${rows.length}  '
      '(ceiling < floor — T1.2 cannot fix these)');
}

/// The per-quintile severity table. This is the view that separates a real fix
/// from a mean shift: an improved mean with a static Q1 is a rejected result.
void printQuintileTable(List<AdversarialRow> severity) {
  print('\n===== SEVERITY BY QUINTILE '
      '(Q1 = shallowest at freeze time) =====');
  print('  Q    n   taps min/p50/max   nodes p50   capture p50   '
      'ceiling p50   unfixable');
  for (var q = 1; q <= 5; q++) {
    final rows = severity.where((r) => r.entry.quintile == q).toList();
    if (rows.isEmpty) continue;
    final taps = [for (final r in rows) r.tapsToWin];
    final nodes = [for (final r in rows) r.nodes];
    final cap = [for (final r in rows) r.captureRate];
    final ceil = [for (final r in rows) r.ceiling.ceilingTapDepth];
    print('  Q$q  ${rows.length.toString().padLeft(3)}   '
        '${percentileInt(taps, 0).toString().padLeft(3)}/'
        '${percentileInt(taps, 0.5).toString().padLeft(3)}/'
        '${percentileInt(taps, 1).toString().padLeft(3)}         '
        '${percentileInt(nodes, 0.5).toString().padLeft(3)}        '
        '${percentileDouble(cap, 0.5).toStringAsFixed(2).padLeft(5)}        '
        '${percentileInt(ceil, 0.5).toString().padLeft(4)}          '
        '${rows.where((r) => r.geometricallyUnfixable).length}');
  }
}

/// Realised sector and core-count composition. Printed so under-representation
/// stays visible in the README rather than being assumed away.
void printComposition(String label, List<AdversarialRow> rows) {
  final bySector = <int, int>{};
  final byCores = <int, int>{};
  for (final r in rows) {
    bySector[r.board.sector] = (bySector[r.board.sector] ?? 0) + 1;
    byCores[r.board.cores] = (byCores[r.board.cores] ?? 0) + 1;
  }
  final sk = bySector.keys.toList()..sort();
  final ck = byCores.keys.toList()..sort();
  print('  $label sectors: ${sk.map((s) => 'S$s=${bySector[s]}').join('  ')}');
  print('  $label cores  : ${ck.map((c) => '$c=${byCores[c]}').join('  ')}');
}

/// The core-selection path distribution — T0.4's optional telemetry, reported.
///
/// A board that reached `legacyFallback` is F1 in its purest form: its cores
/// *are* the last-popped nodes, and no amount of band tuning reaches it. A
/// board on `relaxedBand` says the strict `[0.35, 0.65]` band was too narrow
/// for its wave profile. T1.2 chooses where to put its quality floor from these
/// two counts, and T1.3's balance note asks for the relaxation rate before
/// tuning further.
void printCorePathDistribution(String label, List<AdversarialRow> rows) {
  final byPath = <String, int>{};
  for (final r in rows) {
    final k = r.corePath?.name ?? 'none (coreless board)';
    byPath[k] = (byPath[k] ?? 0) + 1;
  }
  final keys = byPath.keys.toList()..sort();
  print('\n  $label core-selection path:');
  for (final k in keys) {
    print('    ${k.padRight(24)} ${byPath[k]!.toString().padLeft(3)}'
        '/${rows.length}  ${_pct(byPath[k]! / rows.length)}');
  }
  final attempts = [for (final r in rows) r.coreSelectionAttempts];
  print('    candidate enrichments per board: '
      'p50=${percentileInt(attempts, 0.5)}  '
      'p95=${percentileInt(attempts, 0.95)}  '
      'max=${percentileInt(attempts, 1)}');
}
