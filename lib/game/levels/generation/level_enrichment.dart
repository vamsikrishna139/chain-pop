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
  nodes = _markCoreNodes(nodes, tier);
  nodes = _markSpecialNodes(nodes, config, level);
  return LevelData(
    levelId: level.levelId,
    gridWidth: level.gridWidth,
    gridHeight: level.gridHeight,
    playCells: level.playCells,
    nodes: nodes,
  );
}

List<NodeData> _markCoreNodes(List<NodeData> nodes, DifficultyTier tier) {
  if (tier != DifficultyTier.hard && tier != DifficultyTier.expert) {
    return nodes;
  }
  if (nodes.length < 6) return nodes;

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

  final coreIds = picks.map((n) => n.id).toSet();
  return [
    for (final n in nodes) n.copyWith(isCore: coreIds.contains(n.id)),
  ];
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
