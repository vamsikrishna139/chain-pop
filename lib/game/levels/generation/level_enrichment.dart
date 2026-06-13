import 'dart:math';

import '../grid_cell_key.dart';
import '../level.dart';
import '../level_solver.dart';
import 'difficulty_mode.dart';
import 'difficulty_profile.dart';
import 'level_configuration.dart';
import 'level_validator.dart';

/// Post-processes generated [LevelData] with cores, locked nodes, and relays.
LevelData enrichLevel(
  LevelData level,
  LevelConfiguration config,
  DifficultyTier tier,
) {
  var nodes = level.nodes.map((n) => n.clone()).toList();
  nodes = _markCoreNodes(nodes, tier, level);
  nodes = _markSpecialNodes(nodes, config, level);
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
  DifficultyTier tier,
  LevelData level,
) {
  if (tier != DifficultyTier.hard && tier != DifficultyTier.expert) {
    return nodes;
  }
  if (nodes.length < 6) return nodes;

  final probe = _withNodes(level, nodes);
  final waves = LevelSolver.nodeWaveIndices(probe);
  final maxWave =
      waves.isEmpty ? 0 : waves.values.reduce((a, b) => a > b ? a : b);

  // No wave depth (every node exits immediately) ⇒ percentile bands are
  // meaningless; keep the original last-node behaviour.
  Set<int> coreIds = maxWave <= 0
      ? _legacyCoreIds(nodes)
      : _climaxBandCoreIds(nodes, probe, waves, maxWave);
  if (coreIds.length < 3) coreIds = _legacyCoreIds(nodes);

  return [
    for (final n in nodes) n.copyWith(isCore: coreIds.contains(n.id)),
  ];
}

/// Picks up to three guarded, mid-route, spread-out, central nodes as cores by
/// removal-wave percentile. One core is drawn from each third of the band when
/// possible (a reach-1 → reach-2 → climax arc), then the selection tops up from
/// the whole band and, if still short, a widened band. Fully deterministic — no
/// RNG, a pure function of [probe].
Set<int> _climaxBandCoreIds(
  List<NodeData> nodes,
  LevelData probe,
  Map<int, int> waves,
  int maxWave,
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
  void take(Iterable<NodeData> ordered) {
    for (final n in ordered) {
      if (picks.length >= 3) break;
      if (picks.any((p) => p.id == n.id)) continue;
      if (spreadOk(n)) picks.add(n);
    }
  }

  // Pass 1: one core per equal third of the strict band → difficulty arc.
  const step = (_kCoreBandHi - _kCoreBandLo) / 3;
  for (var i = 0; i < 3; i++) {
    final lo = _kCoreBandLo + i * step;
    final hi = i == 2 ? _kCoreBandHi : _kCoreBandLo + (i + 1) * step;
    for (final n in qualifying(lo, hi)) {
      if (picks.any((p) => p.id == n.id)) continue;
      if (spreadOk(n)) {
        picks.add(n);
        break;
      }
    }
  }
  // Pass 2: top up from the full strict band.
  if (picks.length < 3) take(qualifying(_kCoreBandLo, _kCoreBandHi));
  // Pass 3: relax the band once before giving up to the legacy fallback.
  if (picks.length < 3) {
    take(qualifying(_kCoreBandLoRelaxed, _kCoreBandHiRelaxed));
  }

  return picks.map((n) => n.id).toSet();
}

/// Original highest-id (last-popped) core picks. Retained only as the last-resort
/// fallback so a board with no wave depth — or no qualifying in-band guarded
/// nodes — still ships with three cores.
Set<int> _legacyCoreIds(List<NodeData> nodes) {
  final sorted = List<NodeData>.from(nodes)..sort((a, b) => b.id.compareTo(a.id));
  final picks = <NodeData>[];
  for (final n in sorted) {
    if (picks.length >= 3) break;
    if (picks.any((p) => (p.x - n.x).abs() + (p.y - n.y).abs() < 2)) continue;
    picks.add(n);
  }
  while (picks.length < 3 && picks.length < sorted.length) {
    final next = sorted[picks.length];
    if (!picks.contains(next)) picks.add(next);
  }
  return picks.map((n) => n.id).toSet();
}

List<NodeData> _markSpecialNodes(
  List<NodeData> nodes,
  LevelConfiguration config,
  LevelData level,
) {
  final lvl = config.levelId;
  final mode = config.difficulty.mode;
  if (mode != DifficultyMode.hard) return nodes;

  final rng = Random(lvl * 7919 + 13);
  var result = nodes;

  if (lvl >= 26) {
    final candidates = result
        .where(
          (n) =>
              n.kind == NodeKind.normal &&
              !n.isCore &&
              _canSafelyLock(n, result, level),
        )
        .toList()
      ..shuffle(rng);
    final lockCount = lvl >= 45 ? 2 : 1;
    final lockedIds = candidates.take(lockCount).map((n) => n.id).toSet();
    result = [
      for (final n in result)
        lockedIds.contains(n.id) ? n.copyWith(kind: NodeKind.locked) : n,
    ];
  }

  if (lvl >= 51) {
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
    final sorted = List<NodeData>.from(result)..sort((a, b) => b.id.compareTo(a.id));
    final relayCandidates = sorted
        .where(
          (n) =>
              n.kind == NodeKind.normal &&
              !n.isCore &&
              !coreRows.contains(n.y),
        )
        .take(6)
        .toList()
      ..shuffle(rng);
    final validator = LevelValidator();
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
      if (_relayIsSoftlockSafe(probe, candidate.id) &&
          validator.validate(probe).isValid) {
        result = withRelay;
        break;
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
bool _relayIsSoftlockSafe(LevelData level, int relayId) {
  final byCell = <int, NodeData>{
    for (final n in level.nodes) gridCellKey(n.x, n.y): n,
  };
  final relay = level.nodes.firstWhere((n) => n.id == relayId);

  final must = <int>{};
  final stack = <NodeData>[];
  void requireOccupant(int cell) {
    final occ = byCell[cell];
    if (occ != null && occ.id != relay.id && must.add(occ.id)) stack.add(occ);
  }

  for (final c in _rayCellKeys(relay, level)) {
    requireOccupant(c);
  }
  while (stack.isNotEmpty) {
    final node = stack.removeLast();
    for (final c in _rayCellKeys(node, level)) {
      requireOccupant(c);
    }
    // A locked node can only be removed once all four neighbours are gone, so
    // those are prerequisites of clearing it too.
    if (node.kind == NodeKind.locked) {
      for (final (dx, dy) in const [(0, -1), (0, 1), (-1, 0), (1, 0)]) {
        requireOccupant(gridCellKey(node.x + dx, node.y + dy));
      }
    }
  }

  // Worst-case poppable state with the relay removed and its row rotated. The
  // result is relay-free, so monotone solvability ([LevelSolver.isSolvable])
  // is exact.
  final afterPop = <NodeData>[
    for (final n in level.nodes)
      if (!must.contains(n.id) && n.id != relay.id)
        (n.y == relay.y ? n.copyWith(dir: n.dir.rotatedCw) : n),
  ];
  return LevelSolver.isSolvable(LevelData(
    levelId: level.levelId,
    gridWidth: level.gridWidth,
    gridHeight: level.gridHeight,
    playCells: level.playCells,
    nodes: afterPop,
  ));
}

/// Grid-cell keys the node's facing ray passes through, edge-clipped. Rays
/// cross the full bounding grid — `playCells` voids do not stop them.
List<int> _rayCellKeys(NodeData n, LevelData level) {
  final cells = <int>[];
  var x = n.x;
  var y = n.y;
  while (true) {
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
  }
  return cells;
}

bool _canSafelyLock(NodeData node, List<NodeData> nodes, LevelData level) {
  if (!_hasFourNeighbors(node, level)) return false;
  for (final (dx, dy) in [(0, -1), (0, 1), (-1, 0), (1, 0)]) {
    final nx = node.x + dx;
    final ny = node.y + dy;
    for (final other in nodes) {
      if (other.x == nx && other.y == ny && other.id >= node.id) {
        return false;
      }
    }
  }
  return true;
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
