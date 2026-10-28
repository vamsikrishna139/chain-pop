import 'dart:math';
import 'dart:typed_data';

import '../grid_cell_key.dart';
import '../level.dart';
import '../level_solver.dart';
import 'core_metrics.dart';
import 'difficulty_mode.dart';
import 'difficulty_profile.dart';
import 'level_configuration.dart';
import 'level_validator.dart';
import 'metrics.dart';
import 'progression_profile.dart';

/// Post-processes generated [LevelData] with cores, locked nodes, and relays.
LevelData enrichLevel(
  LevelData level,
  LevelConfiguration config,
  DifficultyTier tier, {
  MechanicBudgetOverride? mechanicOverride,

  /// F1 — receives the core-selection outcome for this board, if one was made.
  ///
  /// [CoreSelectionTelemetry.sink] already broadcasts the same record, but it
  /// is a global static that tests set for their own purposes; a caller that
  /// needs the outcome for a *decision* cannot share it. This is the per-call
  /// channel, so the generator can reject a board whose core floor could not
  /// be met instead of shipping it.
  void Function(CoreSelectionRecord record)? onCoreSelection,
}) {
  var nodes = level.nodes.map((n) => n.clone()).toList();
  nodes = _markCoreNodes(
      nodes, config.difficulty.mode, level, mechanicOverride, onCoreSelection);
  nodes = _markSpecialNodes(nodes, config, level, mechanicOverride);
  return LevelData(
    levelId: level.levelId,
    gridWidth: level.gridWidth,
    gridHeight: level.gridHeight,
    playCells: level.playCells,
    nodes: nodes,
  );
}

/// Tap-depth percentile band a core must fall in. Mid-route by design: the
/// player must clear a meaningful slice of the board to expose a core, but the
/// win still fires with ~35% of the board standing so the cascade finale is a
/// real payoff rather than a 2-node mop-up. (The old behaviour — the three
/// highest-id, i.e. last-popped, nodes — made the core-win fire at ~92% cleared,
/// so "going for the cores" was indistinguishable from clearing everything.)
///
/// **T1.1, 2026-08-19 — the band is unchanged; what it measures is not.** Until
/// now the percentile was `waves[id] / maxWave`: *removal-wave* depth, which is
/// a **parallel** quantity — a wave is everything that becomes extractable at
/// once. The win condition is sequential: it fires when the last core is
/// *tapped*, and the number of taps that must precede it is the size of the
/// core's prerequisite closure. The two diverge badly on wide shallow boards,
/// where a node can sit at wave percentile 0.5 while only three taps stand in
/// front of it — which is exactly F1. The band now measures
/// `|closure(n)| / max_m |closure(m)|`, the same relation [CoreMetrics] scores
/// the shipped board with, so selector and metric cannot drift apart.
const double _kCoreBandLo = 0.35;
const double _kCoreBandHi = 0.65;

/// Widened band tried once before falling back to the legacy highest-id picks,
/// so an adversarial board never ships with fewer than three cores.
const double _kCoreBandLoRelaxed = 0.25;
const double _kCoreBandHiRelaxed = 0.78;

/// Which of `_climaxBandCoreIds`'s escape hatches actually produced the cores.
///
/// T0.4's optional telemetry, and the only part of it that touches `lib/`.
/// **Inert by default and behaviour-free**: nothing here is read by generation,
/// no RNG is drawn, and with [CoreSelectionTelemetry.sink] null (its production
/// value) the only cost is a handful of integer increments.
///
/// It exists because T1.2 has to choose where to put a quality floor, and T1.3's
/// balance note asks for the relaxation rate before tuning further. Without it
/// both are designed blind to how often the hatches actually fire — a board
/// whose cores came from `legacyFallback` was never in the climax band at all,
/// and no amount of band tuning will help it.
enum CoreSelectionPath {
  /// Pass 1 alone: one core drawn from each third of the strict band, giving
  /// the intended reach-1 -> reach-2 -> climax arc.
  strictBandArc,

  /// Pass 2: topped up from the full strict band after the arc came up short.
  strictBandTopUp,

  /// Pass 3: the widened band. The first real signal that the strict band is
  /// too narrow for this board.
  relaxedBand,

  /// No wave depth at all — every node exits immediately, so percentile bands
  /// are meaningless and the original last-popped behaviour stands.
  legacyNoWaveDepth,

  /// Every band failed and the selection fell back to the highest-id
  /// (last-popped) nodes. This is F1 in its purest form: the cores *are* the
  /// end of the board.
  legacyFallback,
}

/// One core-selection decision, as reported to [CoreSelectionTelemetry.sink].
class CoreSelectionRecord {
  const CoreSelectionRecord({
    required this.levelId,
    required this.mode,
    required this.path,
    required this.requested,
    required this.selected,
    required this.fromStrictBand,
    required this.fromRelaxedBand,
    required this.coreIds,
    this.floorRequired = 0,
    this.floorAchieved = 0,
    this.repickRungs = 0,
    this.escalated = false,
  });

  final int levelId;
  final DifficultyMode mode;

  /// The furthest hatch that had to be reached.
  final CoreSelectionPath path;

  /// `budget.coreCount` for this level.
  final int requested;

  /// Cores actually marked.
  final int selected;

  /// Picks that came from the strict `[0.35, 0.65]` band (passes 1 and 2).
  final int fromStrictBand;

  /// Additional picks that needed the widened `[0.25, 0.78]` band.
  final int fromRelaxedBand;

  /// The chosen core ids, ascending.
  ///
  /// `enrichLevel` runs once per *candidate*, not once per emitted board, so a
  /// single `generate` call produces several records and only one of them
  /// describes the level that shipped. Carrying the ids lets an offline harness
  /// identify that one by matching against the emitted board's cores, instead
  /// of guessing that the last record wins — which is false whenever the
  /// generator prefers an earlier candidate.
  final List<int> coreIds;

  /// T1.2's mode floor for this board, in taps.
  final int floorRequired;

  /// `coreTapDepth` of the set that actually shipped.
  final int floorAchieved;

  /// Repick rungs the choke point climbed. 0 means the band pick was already
  /// deep enough and nothing was re-picked.
  final int repickRungs;

  /// True when the board could not reach the floor at its nominal core count
  /// and one extra core was added to get there.
  final bool escalated;

  /// False only for boards whose geometry cannot support the floor at all —
  /// the T0.4§d "UNFIXABLE" set. Surfaced rather than hidden.
  bool get floorMet => floorAchieved >= floorRequired;

  @override
  String toString() => 'L$levelId/${mode.name} ${path.name} '
      '$selected/$requested strict=$fromStrictBand relaxed=$fromRelaxedBand '
      'depth=$floorAchieved/$floorRequired rungs=$repickRungs'
      '${escalated ? " escalated" : ""}';
}

/// Opt-in sink for [CoreSelectionRecord]s. Null in production and in every test
/// that does not explicitly set it; set it, run a batch, and clear it.
///
/// Deliberately not an analytics event: this is offline instrumentation for the
/// corpus harness, and routing it through the analytics sink would put it on a
/// path that ships.
class CoreSelectionTelemetry {
  CoreSelectionTelemetry._();

  static void Function(CoreSelectionRecord record)? sink;

  static void _emit(CoreSelectionRecord record) => sink?.call(record);
}

/// Rebuilds a [LevelData] with [nodes] but [level]'s geometry — used to query
/// the solver against a working node list.
LevelData _withNodes(LevelData level, List<NodeData> nodes) => LevelData(
      levelId: level.levelId,
      gridWidth: level.gridWidth,
      gridHeight: level.gridHeight,
      playCells: level.playCells,
      nodes: nodes,
    );

/// Transitive prerequisite closures for every node on a board, plus the
/// derived quantities T1.1's band and T1.2's floor both read.
///
/// One node's closure is the set of nodes that must be removed *before* it can
/// be, plus the node itself — i.e. the taps a player is committed to in order
/// to reach it. The relation is [computeRayPrerequisites], the same one
/// [CoreMetrics] uses, so a board's selected depth and its measured depth are
/// on one scale by construction.
///
/// Purely a function of node positions and directions: blind to `kind`,
/// `isCore` and `phaseGroup`. That is what keeps core selection from touching
/// board geometry (§0.1 of the plan) — it reads geometry and writes flags.
class _ClosureIndex {
  _ClosureIndex._({
    required this.nodes,
    required this.indexOfId,
    required this.words,
    required this.masks,
    required this.sizes,
    required this.maxSize,
  });

  final List<NodeData> nodes;
  final Map<int, int> indexOfId;

  /// 32-bit words per closure. Boards run to a few dozen nodes, so this is 1
  /// or 2 in practice — but sizing it from `n` keeps the structure correct for
  /// any board rather than correct-by-coincidence.
  final int words;

  /// `n × words` row-major bitset: bit `j` of row `i` is set when node `j` is
  /// in node `i`'s prerequisite closure.
  final Uint32List masks;

  /// Popcount of each row, i.e. how many taps that node costs to reach.
  final List<int> sizes;

  /// The deepest single node on the board. The band's percentile denominator.
  final int maxSize;

  factory _ClosureIndex.of(LevelData probe) {
    final nodes = probe.nodes;
    final n = nodes.length;
    final indexOfId = <int, int>{
      for (var i = 0; i < n; i++) nodes[i].id: i,
    };
    final words = n == 0 ? 0 : (n + 31) >> 5;
    final masks = Uint32List(n * words);
    final prereqs = computeRayPrerequisites(probe);
    final sizes = List<int>.filled(n, 0);
    var maxSize = 0;

    for (var i = 0; i < n; i++) {
      final base = i * words;
      final stack = <int>[i];
      var count = 0;
      while (stack.isNotEmpty) {
        final cur = stack.removeLast();
        final w = base + (cur >> 5);
        final bit = 1 << (cur & 31);
        if (masks[w] & bit != 0) continue;
        masks[w] |= bit;
        count++;
        for (final pre in prereqs[nodes[cur].id] ?? const <int>[]) {
          final pi = indexOfId[pre];
          if (pi != null && masks[base + (pi >> 5)] & (1 << (pi & 31)) == 0) {
            stack.add(pi);
          }
        }
      }
      sizes[i] = count;
      if (count > maxSize) maxSize = count;
    }

    return _ClosureIndex._(
      nodes: nodes,
      indexOfId: indexOfId,
      words: words,
      masks: masks,
      sizes: sizes,
      maxSize: maxSize,
    );
  }

  int sizeOf(int id) {
    final i = indexOfId[id];
    return i == null ? 0 : sizes[i];
  }

  /// `CoreMetrics.coreTapDepth` for a candidate core set — the union of the
  /// members' closures. Computed here rather than by enriching a probe board
  /// and calling [CoreMetrics.compute] because the repick loop evaluates
  /// several candidate sets per board and only the union size matters.
  int tapDepthOf(Iterable<int> coreIds) {
    if (words == 0) return 0;
    final acc = Uint32List(words);
    for (final id in coreIds) {
      unionInto(acc, id);
    }
    return popcount(acc);
  }

  /// ORs node [id]'s closure into [acc].
  void unionInto(Uint32List acc, int id) {
    final i = indexOfId[id];
    if (i == null) return;
    final base = i * words;
    for (var w = 0; w < words; w++) {
      acc[w] |= masks[base + w];
    }
  }

  /// Bits node [id]'s closure would add to [acc] — the greedy gain, counted
  /// without allocating a candidate union.
  int gainOver(Uint32List acc, int id) {
    final i = indexOfId[id];
    if (i == null) return 0;
    final base = i * words;
    var gain = 0;
    for (var w = 0; w < words; w++) {
      gain += _popcount32(masks[base + w] & ~acc[w]);
    }
    return gain;
  }

  static int popcount(Uint32List bits) {
    var total = 0;
    for (var w = 0; w < bits.length; w++) {
      total += _popcount32(bits[w]);
    }
    return total;
  }

  static int _popcount32(int v) {
    var x = v & 0xFFFFFFFF;
    var c = 0;
    while (x != 0) {
      x &= x - 1;
      c++;
    }
    return c;
  }
}

/// T1.2 — the per-mode core-quality floor, and the escape valve for boards
/// whose geometry cannot honour it at their nominal core count.
///
/// Expressed two ways because neither alone is right. An absolute tap count
/// alone lets a large board ship a core that is deep in taps but shallow as a
/// *share* of the board; a fraction alone lets a small board ship a 4-tap win
/// and call it 45%. The floor is the larger of the two.
class _CoreFloor {
  const _CoreFloor({
    required this.absoluteTaps,
    required this.tapFraction,
    required this.maxCores,
  });

  /// No published board wins in fewer taps than this. Set to 7 across all three
  /// modes: T0.3's gate is "≤ 6-tap share below 5%", so 7 is the first
  /// non-trivial tap count.
  final int absoluteTaps;

  /// Minimum `coreTapFraction`. Deliberately modest — the band (T1.1) decides
  /// *where* a core sits and the floor only stops it being trivial; a high
  /// fraction floor would override the band on every board and push cores back
  /// towards last-popped, which is the defect, not the fix.
  ///
  /// Hard sits below its own measured baseline (`coreTapFraction` p50 ≈ 0.40)
  /// so the floor barely binds there: Hard is healthy today and P1's job is to
  /// leave it alone.
  final double tapFraction;

  /// Ceiling for the escalation escape valve. Never exceeded, so escalation
  /// cannot quietly rewrite the campaign's core curve.
  final int maxCores;

  int requiredDepth(int totalNodes) {
    final byFraction = (tapFraction * totalNodes).ceil();
    return absoluteTaps > byFraction ? absoluteTaps : byFraction;
  }
}

const Map<DifficultyMode, _CoreFloor> _kCoreFloors = {
  DifficultyMode.easy:
      _CoreFloor(absoluteTaps: 7, tapFraction: 0.45, maxCores: 1),
  DifficultyMode.medium:
      _CoreFloor(absoluteTaps: 7, tapFraction: 0.45, maxCores: 3),
  // Hard carries **no** fraction floor. Measured at Gen V1 its
  // `coreTapFraction` runs p50 0.40 / min 0.24, so any fraction floor worth
  // writing binds on the mode P1 is explicitly required not to move — a 0.35
  // floor alone lifted Hard's minimum from 6 to 9. Hard keeps the absolute
  // floor only, which touches the single shallowest board and nothing else.
  DifficultyMode.hard:
      _CoreFloor(absoluteTaps: 7, tapFraction: 0.0, maxCores: 3),
};

/// Repick rungs the floor may climb before it gives up. Bounded by contract:
/// the loop never regenerates a board, so generation cost is unchanged and
/// contract C1 (zero-fallback) holds structurally rather than by policy.
const int _kMaxCoreRepickRungs = 3;

List<NodeData> _markCoreNodes(
  List<NodeData> nodes,
  DifficultyMode mode,
  LevelData level,
  MechanicBudgetOverride? mechanicOverride, [
  void Function(CoreSelectionRecord record)? onCoreSelection,
]) {
  final budget = budgetForLevel(
    levelId: level.levelId,
    mode: mode,
    mechanicOverride: mechanicOverride,
  );

  if (budget.coreCount == 0) return nodes;
  if (nodes.length < 6) return nodes;

  final probe = _withNodes(level, nodes);
  final closures = _ClosureIndex.of(probe);

  // No depth structure at all (every node is immediately extractable, so every
  // closure is the node itself) ⇒ percentile bands are meaningless; keep the
  // original last-node behaviour.
  _BandSelection selection;
  if (closures.maxSize <= 1) {
    selection = _BandSelection(
      ids: _legacyCoreIds(nodes, budget.coreCount),
      path: CoreSelectionPath.legacyNoWaveDepth,
    );
  } else {
    selection = _climaxBandCoreIds(nodes, probe, closures, budget.coreCount);
  }
  var coreIds = selection.ids;
  if (coreIds.length < budget.coreCount) {
    coreIds = _legacyCoreIds(nodes, budget.coreCount);
    selection = _BandSelection(
      ids: coreIds,
      path: CoreSelectionPath.legacyFallback,
    );
  }

  // THE CHOKE POINT (T1.2). Every core-id set — strict band, relaxed band,
  // hatch #1 inside `_climaxBandCoreIds`, hatch #2 just above — converges here
  // before it can be written onto nodes. A check placed beside either hatch
  // would leak through the other (§0.3).
  final quality = _ensureCoreQuality(
    coreIds: coreIds,
    nodes: nodes,
    probe: probe,
    closures: closures,
    mode: mode,
    requestedCount: budget.coreCount,
  );
  coreIds = quality.ids;

  final record = CoreSelectionRecord(
    levelId: level.levelId,
    mode: mode,
    path: selection.path,
    requested: budget.coreCount,
    selected: coreIds.length,
    fromStrictBand: selection.fromStrictBand,
    fromRelaxedBand: selection.fromRelaxedBand,
    coreIds: coreIds.toList()..sort(),
    floorRequired: quality.required,
    floorAchieved: quality.achieved,
    repickRungs: quality.rungs,
    escalated: quality.escalated,
  );
  CoreSelectionTelemetry._emit(record);
  onCoreSelection?.call(record);

  return [
    for (final n in nodes) n.copyWith(isCore: coreIds.contains(n.id)),
  ];
}

/// A core selection plus the provenance [CoreSelectionTelemetry] reports.
/// Carrying it in a record rather than out-params keeps `_markCoreNodes` a
/// single expression per branch, so the telemetry cannot drift out of step with
/// the selection it describes.
class _BandSelection {
  const _BandSelection({
    required this.ids,
    required this.path,
    this.fromStrictBand = 0,
    this.fromRelaxedBand = 0,
  });

  final Set<int> ids;
  final CoreSelectionPath path;
  final int fromStrictBand;
  final int fromRelaxedBand;
}

/// The outcome of the T1.2 choke point.
class _CoreQualityOutcome {
  const _CoreQualityOutcome({
    required this.ids,
    required this.required,
    required this.achieved,
    required this.rungs,
    required this.escalated,
  });

  final Set<int> ids;

  /// The mode floor for this board, in taps.
  final int required;

  /// `coreTapDepth` of the set that shipped.
  final int achieved;

  /// Repick rungs climbed. 0 means the incoming selection already cleared the
  /// floor and nothing was re-picked.
  final int rungs;

  /// True when the board could not reach the floor at its nominal core count
  /// and one extra core was added to get there.
  final bool escalated;

  bool get met => achieved >= required;
}

/// Guarantees the invariant:
///
///     No published board, in any mode, wins in fewer taps than its mode floor
///     — regardless of which selection path produced its cores.
///
/// …to the extent the board's geometry permits it. Three things happen here,
/// in order, and each is bounded:
///
/// 1. **Accept.** If the incoming selection already clears the floor, nothing
///    moves. On a healthy board this is the only branch that runs.
/// 2. **Repick, up to [_kMaxCoreRepickRungs] rungs.** Each rung re-picks the
///    same number of cores by greedy maximum coverage of prerequisite closures,
///    widening the candidate pool as it climbs: guarded-and-normal (the band's
///    own candidate class) → normal → every node. Widening the *pool* rather
///    than the *band* matters: pass 3 of `_climaxBandCoreIds` already relaxes
///    the band, and relaxing it twice would simply undo T1.1.
/// 3. **Escalate, once.** T0.4§d found the residual: a handful of small boards
///    have no spread-legal core set of the nominal size that reaches the floor
///    — Medium sector 2, which ships a single core, is almost all of them. The
///    declared behaviour for that set is one extra core rather than a silent
///    "best seen", and it is accepted **only if it actually clears the floor**,
///    so a board never gains a core for nothing. [_CoreFloor.maxCores] caps it,
///    which is why it can never fire on Hard or Easy.
///
/// If all of that still falls short the board is geometrically incapable and
/// ships the deepest set seen. That case is counted, not hidden: the telemetry
/// record carries `floorRequired` and `floorAchieved`.
///
/// Never regenerates a board, draws no RNG, and is a pure function of geometry.
_CoreQualityOutcome _ensureCoreQuality({
  required Set<int> coreIds,
  required List<NodeData> nodes,
  required LevelData probe,
  required _ClosureIndex closures,
  required DifficultyMode mode,
  required int requestedCount,
}) {
  final floor = _kCoreFloors[mode]!;
  final required = floor.requiredDepth(nodes.length);

  var bestIds = coreIds;
  var bestDepth = closures.tapDepthOf(coreIds);
  if (bestDepth >= required) {
    return _CoreQualityOutcome(
      ids: bestIds,
      required: required,
      achieved: bestDepth,
      rungs: 0,
      escalated: false,
    );
  }

  final centrality = _centralityOf(nodes);

  // Rung pools, widening. Rung 1 keeps the band's own candidate class so a
  // repick still lands on a node the player must set up for; only when that
  // cannot reach the floor does the guarded requirement come off.
  //
  // Memoised because the ladder is re-run once per escalated core count and
  // rung 1 costs a `LevelSolver.canRemove` per node — the single most
  // expensive thing in this file. `enrichLevel` runs once per *candidate*
  // inside the generator's accept/reject loop, so a repeated solver sweep here
  // is multiplied across the whole K-loop.
  final pools = List<List<NodeData>?>.filled(_kMaxCoreRepickRungs + 1, null);
  List<NodeData> poolForRung(int rung) => pools[rung] ??= switch (rung) {
        1 => [
            for (final n in nodes)
              if (n.kind == NodeKind.normal &&
                  !LevelSolver.canRemove(n, nodes, probe))
                n,
          ],
        2 => [
            for (final n in nodes)
              if (n.kind == NodeKind.normal) n,
          ],
        _ => nodes,
      };

  var rungs = 0;
  for (var rung = 1; rung <= _kMaxCoreRepickRungs; rung++) {
    rungs = rung;
    final candidate = _greedyDeepestCoreSet(
      pool: poolForRung(rung),
      closures: closures,
      count: requestedCount,
      centrality: centrality,
    );
    final depth = closures.tapDepthOf(candidate);
    if (depth > bestDepth) {
      bestIds = candidate;
      bestDepth = depth;
    }
    if (bestDepth >= required) {
      return _CoreQualityOutcome(
        ids: bestIds,
        required: required,
        achieved: bestDepth,
        rungs: rungs,
        escalated: false,
      );
    }
  }

  // Escalation — extra cores, one at a time, accepted only at the first count
  // that clears the floor. Climbing rather than taking a single step matters:
  // the boards that need this are the flattest on the campaign, and a 16-node
  // sector-2 board whose deepest single node is five taps deep reaches eight
  // with two cores and ten with three. Stopping at +1 would leave exactly the
  // boards the invariant exists for.
  for (var k = requestedCount + 1; k <= floor.maxCores; k++) {
    for (var rung = 1; rung <= _kMaxCoreRepickRungs; rung++) {
      final candidate = _greedyDeepestCoreSet(
        pool: poolForRung(rung),
        closures: closures,
        count: k,
        centrality: centrality,
      );
      if (candidate.length < k) continue;
      final depth = closures.tapDepthOf(candidate);
      // Strictly accept-on-clear: a set that still falls short is discarded
      // rather than kept as "best seen", so a board never gains a core for
      // nothing. A geometrically flat board ships its nominal core count.
      if (depth >= required) {
        return _CoreQualityOutcome(
          ids: candidate,
          required: required,
          achieved: depth,
          rungs: rungs,
          escalated: true,
        );
      }
    }
  }

  return _CoreQualityOutcome(
    ids: bestIds,
    required: required,
    achieved: bestDepth,
    rungs: rungs,
    escalated: false,
  );
}

/// Greedy maximum-coverage core set: repeatedly take the spread-legal candidate
/// that adds the most *new* prerequisite taps.
///
/// Coverage of a union of closures is submodular, so greedy is within
/// `1 - 1/e` of optimal and, at these board sizes, almost always exactly
/// optimal — close enough that computing the true optimum over every
/// spread-legal k-subset would buy nothing for the cost. Fully deterministic:
/// ties break on closure size, then centrality, then id.
Set<int> _greedyDeepestCoreSet({
  required List<NodeData> pool,
  required _ClosureIndex closures,
  required int count,
  required double Function(NodeData) centrality,
}) {
  final picks = <NodeData>[];
  final covered = Uint32List(closures.words);

  while (picks.length < count) {
    NodeData? best;
    var bestGain = -1;
    for (final n in pool) {
      if (picks.any((p) => p.id == n.id)) continue;
      if (!picks.every((p) => (p.x - n.x).abs() + (p.y - n.y).abs() >= 2)) {
        continue;
      }
      final gain = closures.gainOver(covered, n.id);
      if (best == null || gain > bestGain) {
        best = n;
        bestGain = gain;
        continue;
      }
      if (gain == bestGain && _prefer(n, best, closures, centrality)) {
        best = n;
      }
    }
    if (best == null) break;
    picks.add(best);
    closures.unionInto(covered, best.id);
  }

  return picks.map((n) => n.id).toSet();
}

/// Deterministic tie-break between two candidates of equal coverage gain:
/// the deeper node, then the more central one, then the lower id.
bool _prefer(
  NodeData a,
  NodeData b,
  _ClosureIndex closures,
  double Function(NodeData) centrality,
) {
  final sa = closures.sizeOf(a.id);
  final sb = closures.sizeOf(b.id);
  if (sa != sb) return sa > sb;
  final ca = centrality(a);
  final cb = centrality(b);
  if (ca != cb) return ca < cb;
  return a.id < b.id;
}

/// Squared distance from the board centroid. Central cores read as the "heart"
/// the player routes toward, so it is the tie-break both the band pass and the
/// repick loop use.
double Function(NodeData) _centralityOf(List<NodeData> nodes) {
  var sx = 0, sy = 0;
  for (final n in nodes) {
    sx += n.x;
    sy += n.y;
  }
  final cx = sx / nodes.length;
  final cy = sy / nodes.length;
  return (n) => (n.x - cx) * (n.x - cx) + (n.y - cy) * (n.y - cy);
}

/// Picks up to three guarded, mid-route, spread-out, central nodes as cores by
/// **tap-depth** percentile (T1.1 — see [_kCoreBandLo]). One core is drawn from
/// each third of the band when possible (a reach-1 → reach-2 → climax arc),
/// then the selection tops up from the whole band and, if still short, a
/// widened band. Fully deterministic — no RNG, a pure function of [probe].
_BandSelection _climaxBandCoreIds(
  List<NodeData> nodes,
  LevelData probe,
  _ClosureIndex closures,
  int count,
) {
  final centrality = _centralityOf(nodes);

  // Candidates in a [lo, hi] percentile slice: normal, guarded (not removable
  // from the opening state, so reaching them needs deliberate setup), sorted
  // central-first with a stable id tie-break.
  List<NodeData> qualifying(double lo, double hi) {
    final out = <NodeData>[];
    for (final n in nodes) {
      if (n.kind != NodeKind.normal) continue;
      final size = closures.sizeOf(n.id);
      if (size == 0) continue;
      final pct = size / closures.maxSize;
      if (pct < lo || pct > hi) continue;
      if (LevelSolver.canRemove(n, nodes, probe)) continue;
      out.add(n);
    }
    out.sort((a, b) {
      final d = centrality(a).compareTo(centrality(b));
      return d != 0 ? d : b.id.compareTo(a.id);
    });
    return out;
  }

  final picks = <NodeData>[];
  bool spreadOk(NodeData n) =>
      picks.every((p) => (p.x - n.x).abs() + (p.y - n.y).abs() >= 2);

  // Pass 1: one core per equal slice of the strict band -> difficulty arc.
  const step = (_kCoreBandHi - _kCoreBandLo) / 3;
  for (var i = 0; i < count; i++) {
    final lo = _kCoreBandLo + i * step;
    final hi = i == count - 1 ? _kCoreBandHi : _kCoreBandLo + (i + 1) * step;
    for (final n in qualifying(lo, hi)) {
      if (picks.any((p) => p.id == n.id)) continue;
      if (spreadOk(n)) {
        picks.add(n);
        break;
      }
    }
  }
  final afterArc = picks.length;

  // Pass 2: top up from the full strict band.
  if (picks.length < count) {
    for (final n in qualifying(_kCoreBandLo, _kCoreBandHi)) {
      if (picks.length >= count) break;
      if (picks.any((p) => p.id == n.id)) continue;
      if (spreadOk(n)) picks.add(n);
    }
  }
  final afterStrictBand = picks.length;

  // Pass 3: relax the band once before giving up to the legacy fallback.
  if (picks.length < count) {
    for (final n in qualifying(_kCoreBandLoRelaxed, _kCoreBandHiRelaxed)) {
      if (picks.length >= count) break;
      if (picks.any((p) => p.id == n.id)) continue;
      if (spreadOk(n)) picks.add(n);
    }
  }

  if (picks.length >= count) {
    return _BandSelection(
      ids: picks.take(count).map((n) => n.id).toSet(),
      path: picks.length > afterStrictBand
          ? CoreSelectionPath.relaxedBand
          : (afterArc >= count
              ? CoreSelectionPath.strictBandArc
              : CoreSelectionPath.strictBandTopUp),
      fromStrictBand: afterStrictBand,
      fromRelaxedBand: picks.length - afterStrictBand,
    );
  }

  picks.clear();
  final allCandidates = List<NodeData>.from(nodes);
  allCandidates.sort((a, b) => b.id.compareTo(a.id));
  return _BandSelection(
    ids: allCandidates.take(count).map((n) => n.id).toSet(),
    path: CoreSelectionPath.legacyFallback,
  );
}

/// Original highest-id (last-popped) core picks. Retained only as the last-resort
/// fallback so a board with no wave depth — or no qualifying in-band guarded
/// nodes — still ships with three cores.
Set<int> _legacyCoreIds(List<NodeData> nodes, int count) {
  final sorted = List<NodeData>.from(nodes)
    ..sort((a, b) => b.id.compareTo(a.id));
  final picks = <NodeData>[];
  for (final n in sorted) {
    if (picks.length >= count) break;
    if (picks.any((p) => (p.x - n.x).abs() + (p.y - n.y).abs() < 2)) continue;
    picks.add(n);
  }
  while (picks.length < count && picks.length < sorted.length) {
    final next = sorted[picks.length];
    if (!picks.contains(next)) picks.add(next);
  }
  return picks.map((n) => n.id).toSet();
}

List<NodeData> _markSpecialNodes(
  List<NodeData> nodes,
  LevelConfiguration config,
  LevelData level,
  MechanicBudgetOverride? mechanicOverride,
) {
  final lvl = level.levelId;
  final mode = config.difficulty.mode;

  final rng = Random(lvl * 7919 + 13);
  var result = nodes;

  final budget = budgetForLevel(
    levelId: lvl,
    mode: mode,
    mechanicOverride: mechanicOverride,
  );

  if (budget.lockCount > 0) {
    final candidates = result
        .where(
          (n) =>
              n.kind == NodeKind.normal &&
              !n.isCore &&
              _canSafelyLock(n, result, level),
        )
        .toList()
      ..shuffle(rng);
    if (candidates.length < budget.lockCount) {
      // Dense silhouettes (rectangle, diamond) starve the interior-only rule
      // *structurally*, not by chance: the constructor seeds its frontier from
      // the silhouette's boundary and every later placement lands next to an
      // already-placed cell, so on a solid mask each node except the very
      // first has a higher-id orthogonal neighbour — and that first node sits
      // on the boundary, where [_hasFourNeighbors] rejects it. The pool is
      // then empty on *every* attempt, so retrying cannot help: milestone
      // slots on those silhouettes could never seat their lock budget and
      // burned all 40 seeded attempts before silently shipping an ordinary
      // procedural board (see `milestone_seeds.dart`, L150/L725).
      //
      // Top up from a relaxed pool that keeps the part of the rule that
      // matters — every occupied orthogonal neighbour must pop first, so the
      // canonical id-order solution still clears the board — and drops only
      // the geometric "interior cell" requirement, in exchange for demanding
      // that the lock actually *starts* locked (≥ 1 occupied neighbour). A
      // boundary node with three neighbours is a real lock; an interior node
      // with none is the decorative case the old rule already allowed.
      //
      // Appended after the strict pool, so any board that can satisfy the
      // strict rule picks exactly what it picked before.
      final strictIds = {for (final n in candidates) n.id};
      candidates.addAll(
        result
            .where(
              (n) =>
                  n.kind == NodeKind.normal &&
                  !n.isCore &&
                  !strictIds.contains(n.id) &&
                  _canSafelyLockRelaxed(n, result),
            )
            .toList()
          ..shuffle(rng),
      );
    }
    final lockedIds =
        candidates.take(budget.lockCount).map((n) => n.id).toSet();
    result = [
      for (final n in result)
        lockedIds.contains(n.id) ? n.copyWith(kind: NodeKind.locked) : n,
    ];
  }

  // Phase gates are assigned HERE, before relays, and the ordering is
  // load-bearing.
  //
  // They used to be assigned last, after the relay block below. A phase gate
  // strictly *tightens* legal tap order, so `_relayIsSoftlockSafe` was proving
  // its worst case against a board that never shipped: same relay, same
  // rotation, but every node in phase group 0. Measured on `hard L592`, whose
  // relay is poppable on tap 1 (`must` is empty, so the proof's worst case is
  // the full board):
  //
  //   worst case with phase groups stripped — what the proof saw : SOLVABLE
  //   worst case as shipped                 — what the player got: UNSOLVABLE
  //
  // The relay was accepted and the board could be tapped into a dead end; the
  // 600-level autoplay found it on 1 of 3 routes. Same defect shape as §0.3's
  // two core fallbacks: a correctness check that does not sit at the last
  // choke point is not a check.
  //
  // Moving the block is safe and leaves phase assignment itself unchanged —
  // `chunkSize` reads `result.length`, and the relay block substitutes node
  // kinds without adding or removing any node.
  if (budget.phaseGateCount > 0) {
    final groups = budget.phaseGateCount + 1;
    // Node ids are 0-based and contiguous, and the canonical solve order *is*
    // id order, so chunking by id keeps the constructed solution legal while
    // forbidding the out-of-order deviations the gate is meant to block.
    final chunkSize = (result.length / groups).ceil();
    result = [
      for (final n in result)
        n.copyWith(
            phaseGroup: (n.id ~/ chunkSize).clamp(0, budget.phaseGateCount)),
    ];
  }

  if (budget.relayCount > 0) {
    // A relay rotates its whole row when popped, which can spin arrows into
    // permanent face-offs. Relay-free Chain Pop can never soft-lock (removing a
    // node only ever frees rays), so a relay is the *only* mechanic that can
    // strand the board — and the danger is that the player pops it at the wrong
    // moment, not just in the canonical order. Keep relays out of core rows (a
    // stranded core is unwinnable) and only accept a candidate that
    // [_relayIsSoftlockSafe] proves stays solvable no matter when it is popped
    // AND that keeps the canonical ID-order solution valid — [LevelGenerator]
    // re-runs [LevelValidator] on the enriched output, so a candidate that
    // breaks ID order would get the whole level discarded downstream.
    // If no candidate survives, ship the level without a relay.
    final coreRows = {for (final n in result.where((n) => n.isCore)) n.y};
    final sorted = List<NodeData>.from(result)
      ..sort((a, b) => b.id.compareTo(a.id));
    final relayCandidates = sorted
        .where(
          (n) =>
              n.kind == NodeKind.normal && !n.isCore && !coreRows.contains(n.y),
        )
        .take(10)
        .toList()
      ..shuffle(rng);
    final validator = LevelValidator();

    if (budget.relayCount == 1) {
      for (final candidate in relayCandidates) {
        final withRelay = [
          for (final n in result)
            n.id == candidate.id ? n.copyWith(kind: NodeKind.relay) : n,
        ];
        final probe = LevelData(
          levelId: level.levelId,
          gridWidth: level.gridWidth,
          gridHeight: level.gridHeight,
          playCells: level.playCells,
          nodes: withRelay,
        );
        if (_relayIsSoftlockSafe(probe, {candidate.id}) &&
            validator.validate(probe).isValid) {
          result = withRelay;
          break;
        }
      }
    } else if (budget.relayCount == 2) {
      // `relay_softlock_property_test`'s two-relay case still fails: it finds
      // boards that softlock despite `_relayIsSoftlockSafe` returning true, so
      // the predicate is unsound for two relays. Nothing budgets two relays
      // today — measured across all three modes x 600 levels, every shipped
      // board has 0 or 1 — so this path is unreachable and the defect is
      // latent. It is left in place rather than deleted because the sound
      // single-relay argument does not obviously extend, and finding out why
      // is the work the property test exists to force.
      //
      // Anything that starts budgeting two relays must fix the predicate
      // first. Solvability is invariant C5; an unreachable unsound path is
      // tolerable, a reachable one is not. Deliberately NOT an `assert(false)`
      // — the property test drives this exact path to demonstrate the defect,
      // and an assertion here would replace its useful failure with a crash.
      bool found = false;
      for (int i = 0; i < relayCandidates.length; i++) {
        for (int j = i + 1; j < relayCandidates.length; j++) {
          final c1 = relayCandidates[i];
          final c2 = relayCandidates[j];
          if (c1.y == c2.y) continue;

          final withRelays = [
            for (final n in result)
              (n.id == c1.id || n.id == c2.id)
                  ? n.copyWith(kind: NodeKind.relay)
                  : n,
          ];
          final probe = LevelData(
            levelId: level.levelId,
            gridWidth: level.gridWidth,
            gridHeight: level.gridHeight,
            playCells: level.playCells,
            nodes: withRelays,
          );
          if (_relayIsSoftlockSafe(probe, {c1.id, c2.id}) &&
              validator.validate(probe).isValid) {
            result = withRelays;
            found = true;
            break;
          }
        }
        if (found) break;
      }
    }
  }

  return result;
}

/// True if [level] — which must contain exactly the single relay [relayId] —
/// can never be soft-locked, no matter when the player pops the relay.
///
/// Why this is sound and O(n) rather than an exhaustive playout: relay-free
/// Chain Pop is *monotone* — removing a node only clears blockers from other
/// nodes' rays, so a solvable board stays solvable under any legal-move order.
/// The relay's row rotation is the one non-monotone event. Before it fires the
/// board is effectively relay-free, so the set of nodes that *must* already be
/// gone for the relay to be poppable is fixed: the occupants of the relay's ray
/// plus, transitively, the occupants of *their* rays (and a locked node's
/// neighbours). Call that closure `must`. The largest — therefore hardest —
/// reachable state in which the relay is poppable is exactly `allNodes \ must`;
/// every other poppable state has *more* nodes removed and is easier by
/// monotonicity. So if popping the relay from that worst case leaves a solvable
/// (now relay-free) board, every reachable pop is safe too.
bool _relayIsSoftlockSafe(LevelData level, Set<int> relayIds) {
  if (relayIds.isEmpty) return LevelSolver.isSolvable(level);

  final byCell = <int, NodeData>{
    for (final n in level.nodes) gridCellKey(n.x, n.y): n,
  };

  var foundPoppableRelay = false;
  for (final relayId in relayIds) {
    final relay = level.nodes.firstWhere((n) => n.id == relayId);

    final must = <int>{};
    final stack = <NodeData>[];
    bool canBePoppedFirst = true;

    void requireOccupant(int cell) {
      if (!canBePoppedFirst) return;
      final occ = byCell[cell];
      if (occ != null && occ.id != relay.id) {
        if (relayIds.contains(occ.id)) {
          canBePoppedFirst = false;
        } else if (must.add(occ.id)) {
          stack.add(occ);
        }
      }
    }

    for (final c in _rayCellKeys(relay, level)) {
      requireOccupant(c);
    }
    while (stack.isNotEmpty && canBePoppedFirst) {
      final node = stack.removeLast();
      for (final c in _rayCellKeys(node, level)) {
        requireOccupant(c);
      }
      if (node.kind == NodeKind.locked) {
        for (final (dx, dy) in const [(0, -1), (0, 1), (-1, 0), (1, 0)]) {
          requireOccupant(gridCellKey(node.x + dx, node.y + dy));
        }
      }
    }

    if (!canBePoppedFirst) continue;
    foundPoppableRelay = true;

    final afterPop = <NodeData>[
      for (final n in level.nodes)
        if (!must.contains(n.id) && n.id != relay.id)
          (n.y == relay.y ? n.copyWith(dir: n.dir.rotatedCw) : n),
    ];

    final nextLevel = LevelData(
      levelId: level.levelId,
      gridWidth: level.gridWidth,
      gridHeight: level.gridHeight,
      playCells: level.playCells,
      nodes: afterPop,
    );
    final nextRelays = relayIds.difference({relayId});
    if (!_relayIsSoftlockSafe(nextLevel, nextRelays)) {
      return false;
    }
  }
  return foundPoppableRelay;
}

/// Grid-cell keys the node's facing ray passes through, edge-clipped. Rays
/// cross the full bounding grid — `playCells` voids do not stop them.
List<int> _rayCellKeys(NodeData n, LevelData level) {
  final cells = <int>[];
  var x = n.x;
  var y = n.y;
  var hops = 0;

  while (hops < 50) {
    switch (n.dir) {
      case Direction.up:
        y--;
      case Direction.down:
        y++;
      case Direction.left:
        x--;
      case Direction.right:
        x++;
    }
    if (x < 0 || x >= level.gridWidth || y < 0 || y >= level.gridHeight) break;
    cells.add(gridCellKey(x, y));

    if (level.portalPairs.isNotEmpty) {
      for (final p in level.portalPairs) {
        if (p.x1 == x && p.y1 == y) {
          x = p.x2;
          y = p.y2;
          break;
        } else if (p.x2 == x && p.y2 == y) {
          x = p.x1;
          y = p.y1;
          break;
        }
      }
    }
    hops++;
  }
  return cells;
}

bool _canSafelyLock(NodeData node, List<NodeData> nodes, LevelData level) {
  if (!_hasFourNeighbors(node, level)) return false;
  return _neighboursAllPopFirst(node, nodes).canLock;
}

/// Boundary-tolerant variant of [_canSafelyLock] used only to top up a starved
/// lock pool: same id-order safety, but the node may sit on the grid edge and
/// must have at least one occupied orthogonal neighbour so the lock is live at
/// the start of the level rather than decorative.
bool _canSafelyLockRelaxed(NodeData node, List<NodeData> nodes) {
  final (:canLock, :neighbourCount) = _neighboursAllPopFirst(node, nodes);
  return canLock && neighbourCount > 0;
}

/// Whether every node orthogonally adjacent to [node] is removed before it in
/// the canonical id order — the condition that keeps a locked node clearable —
/// plus how many such neighbours there are.
({bool canLock, int neighbourCount}) _neighboursAllPopFirst(
  NodeData node,
  List<NodeData> nodes,
) {
  var neighbourCount = 0;
  for (final (dx, dy) in [(0, -1), (0, 1), (-1, 0), (1, 0)]) {
    final nx = node.x + dx;
    final ny = node.y + dy;
    for (final other in nodes) {
      if (other.x == nx && other.y == ny) {
        if (other.id >= node.id) return (canLock: false, neighbourCount: 0);
        neighbourCount++;
      }
    }
  }
  return (canLock: true, neighbourCount: neighbourCount);
}

bool _hasFourNeighbors(NodeData node, LevelData level) {
  var count = 0;
  for (final (dx, dy) in [(0, -1), (0, 1), (-1, 0), (1, 0)]) {
    final nx = node.x + dx;
    final ny = node.y + dy;
    if (nx < 0 || nx >= level.gridWidth || ny < 0 || ny >= level.gridHeight) {
      continue;
    }
    count++;
  }
  return count == 4;
}
