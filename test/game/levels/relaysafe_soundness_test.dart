import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:chain_pop/game/levels/level.dart';
import 'package:chain_pop/game/levels/level_solver.dart';
import 'package:chain_pop/game/levels/grid_cell_key.dart';

// ---- candidate safety check (proposed implementation, mirrored) ----
List<int> _rayCells(NodeData n, LevelData level) {
  final cells = <int>[];
  var x = n.x, y = n.y;
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

bool isRelaySafe(LevelData level, int relayId) {
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

  for (final c in _rayCells(relay, level)) {
    requireOccupant(c);
  }
  while (stack.isNotEmpty) {
    final node = stack.removeLast();
    for (final c in _rayCells(node, level)) {
      requireOccupant(c);
    }
    if (node.kind == NodeKind.locked) {
      for (final (dx, dy) in const [(0, -1), (0, 1), (-1, 0), (1, 0)]) {
        requireOccupant(gridCellKey(node.x + dx, node.y + dy));
      }
    }
  }
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

// ---- exhaustive ground truth ----
String _key(List<NodeData> nodes) =>
    (nodes.map((n) => '${n.id}:${n.dir.index}').toList()..sort()).join('|');

List<NodeData> _legalMoves(List<NodeData> nodes, LevelData level) {
  final positions = <int>{for (final n in nodes) gridCellKey(n.x, n.y)};
  final out = <NodeData>[];
  for (final n in nodes) {
    positions.remove(gridCellKey(n.x, n.y));
    if (LevelSolver.canRemoveWithPositions(n, positions, level)) out.add(n);
    positions.add(gridCellKey(n.x, n.y));
  }
  return out;
}

List<NodeData> _apply(List<NodeData> nodes, NodeData n) {
  var next = [for (final m in nodes) if (m.id != n.id) m.clone()];
  if (n.kind == NodeKind.relay) {
    next = [for (final m in next) m.y == n.y ? m.copyWith(dir: m.dir.rotatedCw) : m];
  }
  return next;
}

bool _clearable(List<NodeData> nodes, LevelData level, Map<String, bool> memo) {
  if (nodes.isEmpty) return true;
  final k = _key(nodes);
  final c = memo[k];
  if (c != null) return c;
  memo[k] = false;
  for (final n in _legalMoves(nodes, level)) {
    if (_clearable(_apply(nodes, n), level, memo)) {
      memo[k] = true;
      return true;
    }
  }
  return false;
}

bool softlockFree(LevelData level) {
  final memo = <String, bool>{};
  final visited = <String>{};
  final stack = <List<NodeData>>[level.nodes.map((n) => n.clone()).toList()];
  while (stack.isNotEmpty) {
    final cur = stack.removeLast();
    if (!visited.add(_key(cur))) continue;
    if (cur.isNotEmpty && !_clearable(cur, level, memo)) return false;
    for (final n in _legalMoves(cur, level)) {
      stack.add(_apply(cur, n));
    }
  }
  return true;
}

const _dirs = Direction.values;

void main() {
  test('fuzz: isRelaySafe(true) implies exhaustively softlock-free', () {
    var safeCount = 0;
    var unsafeCount = 0;
    var conservative = 0; // unsafe-but-actually-free (allowed)
    final rng = Random(20260611);

    for (var iter = 0; iter < 4000; iter++) {
      final gw = 3 + rng.nextInt(3); // 3..5
      final gh = 3 + rng.nextInt(3);
      final count = 4 + rng.nextInt(6); // 4..9 nodes
      final cells = <int>{};
      final nodes = <NodeData>[];
      var id = 0;
      var guard = 0;
      while (nodes.length < count && guard++ < 80) {
        final x = rng.nextInt(gw);
        final y = rng.nextInt(gh);
        final key = gridCellKey(x, y);
        if (!cells.add(key)) continue;
        nodes.add(NodeData(
          id: id++,
          x: x,
          y: y,
          dir: _dirs[rng.nextInt(4)],
        ));
      }
      final base = LevelData(
          levelId: 1, gridWidth: gw, gridHeight: gh, nodes: nodes);
      // Only consider relay-free boards that are themselves solvable.
      if (!LevelSolver.isSolvable(base)) continue;

      for (final cand in nodes) {
        final withRelay = LevelData(
          levelId: 1,
          gridWidth: gw,
          gridHeight: gh,
          nodes: [
            for (final n in nodes)
              n.id == cand.id ? n.copyWith(kind: NodeKind.relay) : n,
          ],
        );
        final safe = isRelaySafe(withRelay, cand.id);
        final free = softlockFree(withRelay);
        if (safe) {
          safeCount++;
          expect(free, isTrue,
              reason: 'FALSE-SAFE board: ${nodes.map((n) => "#${n.id}@${n.x},${n.y}:${n.dir.name}").join(" ")} '
                  '| relay=#${cand.id}');
        } else {
          unsafeCount++;
          if (free) conservative++;
        }
      }
    }
    print('fuzz done: safe=$safeCount unsafe=$unsafeCount '
        '(of which actually-free=$conservative)');
    expect(safeCount, greaterThan(100));
  });
}
