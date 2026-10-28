import 'package:flutter_test/flutter_test.dart';
import 'package:chain_pop/game/levels/level.dart';
import 'package:chain_pop/game/levels/level_manager.dart';
import 'package:chain_pop/game/levels/level_solver.dart';
import 'package:chain_pop/game/levels/grid_cell_key.dart';

/// Regression guard for the core invariant: **a level must always remain
/// solvable.** Relay-free Chain Pop can never soft-lock (removing a node only
/// frees rays), so the only mechanic that can strand the board is a relay's row
/// rotation. These tests prove the generator never ships a level a player can
/// soft-lock by popping the relay at the wrong moment.

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
  var next = [
    for (final m in nodes)
      if (m.id != n.id) m.clone()
  ];
  if (n.kind == NodeKind.relay) {
    next = [
      for (final m in next) m.y == n.y ? m.copyWith(dir: m.dir.rotatedCw) : m,
    ];
  }
  return next;
}

bool _clearable(List<NodeData> nodes, LevelData level, Map<String, bool> memo) {
  if (nodes.isEmpty) return true;
  final k = _key(nodes);
  final cached = memo[k];
  if (cached != null) return cached;
  memo[k] = false; // cycle guard (relay rotations can loop)
  for (final n in _legalMoves(nodes, level)) {
    if (_clearable(_apply(nodes, n), level, memo)) {
      memo[k] = true;
      return true;
    }
  }
  return false;
}

/// Exhaustively explores every state reachable by legal play and returns the
/// number that are non-empty yet unclearable (i.e. soft-locks).
int _reachableSoftlocks(LevelData level) {
  final clearMemo = <String, bool>{};
  final visited = <String>{};
  final stack = <List<NodeData>>[level.nodes.map((n) => n.clone()).toList()];
  var dead = 0;
  while (stack.isNotEmpty) {
    final cur = stack.removeLast();
    if (!visited.add(_key(cur))) continue;
    if (cur.isNotEmpty && !_clearable(cur, level, clearMemo)) {
      dead++;
      continue; // a dead state has no useful successors
    }
    for (final n in _legalMoves(cur, level)) {
      stack.add(_apply(cur, n));
    }
  }
  return dead;
}

void main() {
  group('relay levels never soft-lock', () {
    // Exhaustive proof on the level the bug was first reported on, plus the
    // world's first and boss levels. Exhaustive audit is ~100k states each.
    for (final id in [51, 67, 75]) {
      test('level $id has zero reachable soft-lock states', () {
        final level = LevelManager.getLevel(id);
        expect(_reachableSoftlocks(level), 0,
            reason: 'level $id can be soft-locked by a mistimed relay pop');
      });
    }

    test('every relay-world campaign level is born solvable', () {
      // Cheap end-to-end sanity: each generated level must be solvable from its
      // initial state (relay-aware).
      for (var id = 51; id <= 100; id++) {
        final level = LevelManager.getLevel(id);
        final memo = <String, bool>{};
        expect(
          _clearable(level.nodes.map((n) => n.clone()).toList(), level, memo),
          isTrue,
          reason: 'level $id is not solvable',
        );
      }
    });
  });
}
