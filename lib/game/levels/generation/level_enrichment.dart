import 'dart:math';

import '../level.dart';
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
    // permanent face-offs. Keep relays out of core rows (a stranded core is
    // unwinnable), and only accept a candidate whose rotation the relay-aware
    // validator confirms still leaves the canonical solution playable. If no
    // candidate survives, ship the level without a relay.
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
      if (validator.validate(probe).isValid) {
        result = withRelay;
        break;
      }
    }
  }

  return result;
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
