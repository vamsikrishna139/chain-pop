import 'dart:math';

import '../grid_cell_key.dart';
import '../level.dart';
import '../level_solver.dart';
import 'difficulty_mode.dart';
import 'difficulty_profile.dart';
import 'level_configuration.dart';
import 'level_validator.dart';
import 'progression_profile.dart';

/// Post-processes generated [LevelData] with cores, locked nodes, and relays.
LevelData enrichLevel(
  LevelData level,
  LevelConfiguration config,
  DifficultyTier tier, {
  MechanicBudgetOverride? mechanicOverride,
}) {
  var nodes = level.nodes.map((n) => n.clone()).toList();
  nodes =
      _markCoreNodes(nodes, config.difficulty.mode, level, mechanicOverride);
  nodes = _markSpecialNodes(nodes, config, level, mechanicOverride);
  return LevelData(
    levelId: level.levelId,
    gridWidth: level.gridWidth,
    gridHeight: level.gridHeight,
    playCells: level.playCells,
    nodes: nodes,
  );
}

/// Removal-wave percentile band a core must fall in. Mid-route by design: the
/// player must clear a meaningful slice of the board to expose a core, but the
/// win still fires with ~35% of the board standing so the cascade finale is a
/// real payoff rather than a 2-node mop-up. (The old behaviour — the three
/// highest-id, i.e. last-popped, nodes — made the core-win fire at ~92% cleared,
/// so "going for the cores" was indistinguishable from clearing everything.)
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

  @override
  String toString() => 'L$levelId/${mode.name} ${path.name} '
      '$selected/$requested strict=$fromStrictBand relaxed=$fromRelaxedBand';
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

List<NodeData> _markCoreNodes(
  List<NodeData> nodes,
  DifficultyMode mode,
  LevelData level,
  MechanicBudgetOverride? mechanicOverride,
) {
  final budget = budgetForLevel(
    levelId: level.levelId,
    mode: mode,
    mechanicOverride: mechanicOverride,
  );

  if (budget.coreCount == 0) return nodes;
  if (nodes.length < 6) return nodes;

  final probe = _withNodes(level, nodes);
  final waves = LevelSolver.nodeWaveIndices(probe);
  final maxWave =
      waves.isEmpty ? 0 : waves.values.reduce((a, b) => a > b ? a : b);

  // No wave depth (every node exits immediately) ⇒ percentile bands are
  // meaningless; keep the original last-node behaviour.
  _BandSelection selection;
  if (maxWave <= 0) {
    selection = _BandSelection(
      ids: _legacyCoreIds(nodes, budget.coreCount),
      path: CoreSelectionPath.legacyNoWaveDepth,
    );
  } else {
    selection =
        _climaxBandCoreIds(nodes, probe, waves, maxWave, budget.coreCount);
  }
  var coreIds = selection.ids;
  if (coreIds.length < budget.coreCount) {
    coreIds = _legacyCoreIds(nodes, budget.coreCount);
    selection = _BandSelection(
      ids: coreIds,
      path: CoreSelectionPath.legacyFallback,
    );
  }

  CoreSelectionTelemetry._emit(
    CoreSelectionRecord(
      levelId: level.levelId,
      mode: mode,
      path: selection.path,
      requested: budget.coreCount,
      selected: coreIds.length,
      fromStrictBand: selection.fromStrictBand,
      fromRelaxedBand: selection.fromRelaxedBand,
      coreIds: coreIds.toList()..sort(),
    ),
  );

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

/// Picks up to three guarded, mid-route, spread-out, central nodes as cores by
/// removal-wave percentile. One core is drawn from each third of the band when
/// possible (a reach-1 → reach-2 → climax arc), then the selection tops up from
/// the whole band and, if still short, a widened band. Fully deterministic — no
/// RNG, a pure function of [probe].
_BandSelection _climaxBandCoreIds(
  List<NodeData> nodes,
  LevelData probe,
  Map<int, int> waves,
  int maxWave,
  int count,
) {
  // Board centroid, for a centrality tie-break: central cores read as the
  // "heart" the player routes toward.
  var sx = 0, sy = 0;
  for (final n in nodes) {
    sx += n.x;
    sy += n.y;
  }
  final cx = sx / nodes.length;
  final cy = sy / nodes.length;
  double centrality(NodeData n) =>
      (n.x - cx) * (n.x - cx) + (n.y - cy) * (n.y - cy);

  // Candidates in a [lo, hi] percentile slice: normal, guarded (not removable
  // from the opening state, so reaching them needs deliberate setup), sorted
  // central-first with a stable id tie-break.
  List<NodeData> qualifying(double lo, double hi) {
    final out = <NodeData>[];
    for (final n in nodes) {
      if (n.kind != NodeKind.normal) continue;
      final w = waves[n.id];
      if (w == null) continue;
      final pct = w / maxWave;
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
