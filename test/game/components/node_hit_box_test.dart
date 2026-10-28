// P2 — the node interaction target is the full cell, not the painted tile,
// and any point on the board resolves to exactly one node.
//
// The painted sprite stays at `cellSize × 0.82`; only `containsLocalPoint`
// changes. These tests exercise that predicate directly against a grid of
// components laid out exactly as `ChainPopGame` lays them out (cell centres,
// centre anchor), which is what Flame's hit-test walk consults.

import 'package:chain_pop/game/components/node_component.dart';
import 'package:chain_pop/game/levels/level.dart';
import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';

const double kCell = 40.2; // 8-column board on the 390x844 reference device.

NodeComponent _nodeAt(int x, int y, {double cellSize = kCell}) {
  final c = NodeComponent(
    data: NodeData(id: y * 100 + x + 1, x: x, y: y, dir: Direction.up),
    cellSize: cellSize,
  );
  // Mirrors NodeComponent._updatePositionFromGrid (called from onLoad, which
  // needs a mounted game; the geometry under test is entirely local).
  c.position = Vector2((x + 0.5) * cellSize, (y + 0.5) * cellSize);
  return c;
}

/// Board-space point → the component's local space (centre anchor).
Vector2 _local(NodeComponent c, Vector2 board) =>
    board - c.position + c.size / 2;

/// Every node whose hit region claims [board].
List<NodeComponent> _hits(List<NodeComponent> nodes, Vector2 board) => [
      for (final n in nodes)
        if (n.containsLocalPoint(_local(n, board))) n
    ];

void main() {
  group('node hit box covers the whole cell', () {
    final node = _nodeAt(3, 4);

    test('the painted tile is still 0.82 of the cell', () {
      // Vector2 stores float32, hence the loose tolerance.
      expect(node.size.x, closeTo(kCell * 0.82, 1e-3));
    });

    test('accepts the cell centre', () {
      final centre = Vector2(3.5 * kCell, 4.5 * kCell);
      expect(node.containsLocalPoint(_local(node, centre)), isTrue);
    });

    test('accepts points in the gutter the old 0.82 box rejected', () {
      // Just inside the cell edge — outside the sprite, inside the cell.
      for (final p in [
        Vector2(3.02 * kCell, 4.5 * kCell), // left gutter
        Vector2(3.98 * kCell, 4.5 * kCell), // right gutter
        Vector2(3.5 * kCell, 4.02 * kCell), // top gutter
        Vector2(3.5 * kCell, 4.98 * kCell), // bottom gutter
        Vector2(3.02 * kCell, 4.02 * kCell), // corner of the cell
      ]) {
        expect(node.containsLocalPoint(_local(node, p)), isTrue,
            reason: 'board point $p should hit the node at (3,4)');
      }
    });

    test('rejects points in the neighbouring cell', () {
      for (final p in [
        Vector2(2.5 * kCell, 4.5 * kCell),
        Vector2(4.5 * kCell, 4.5 * kCell),
        Vector2(3.5 * kCell, 3.5 * kCell),
        Vector2(3.5 * kCell, 5.5 * kCell),
      ]) {
        expect(node.containsLocalPoint(_local(node, p)), isFalse,
            reason: 'board point $p belongs to a neighbour');
      }
    });

    test('the effective target is a full 40.2px, not 33px', () {
      // Width of the accepted x-interval at the cell's vertical centre.
      var lo = double.infinity, hi = -double.infinity;
      for (var i = 0; i <= 2000; i++) {
        final x = 3.0 * kCell + kCell * i / 2000.0;
        final p = Vector2(x, 4.5 * kCell);
        if (!node.containsLocalPoint(_local(node, p))) continue;
        lo = lo > x ? x : lo;
        hi = hi < x ? x : hi;
      }
      expect(hi - lo, closeTo(kCell, 0.1));
      expect(hi - lo, greaterThan(kCell * 0.82));
    });
  });

  group('every tap resolves to exactly one node', () {
    // A fully packed 8x8 board — the worst case for ambiguity.
    final nodes = [
      for (var y = 0; y < 8; y++)
        for (var x = 0; x < 8; x++) _nodeAt(x, y),
    ];

    test('centre and all four cell corners of every node hit exactly one', () {
      for (var y = 0; y < 8; y++) {
        for (var x = 0; x < 8; x++) {
          final probes = <String, Vector2>{
            'centre': Vector2((x + 0.5) * kCell, (y + 0.5) * kCell),
            'topLeft': Vector2(x * kCell, y * kCell),
            'topRight': Vector2((x + 1) * kCell - 0.05, y * kCell),
            'bottomLeft': Vector2(x * kCell, (y + 1) * kCell - 0.05),
            'bottomRight':
                Vector2((x + 1) * kCell - 0.05, (y + 1) * kCell - 0.05),
          };
          probes.forEach((label, p) {
            final hits = _hits(nodes, p);
            expect(hits.length, 1,
                reason: '$label of cell ($x,$y) hit ${hits.length} nodes '
                    '(${hits.map((n) => "${n.data.x},${n.data.y}").join(" | ")})');
            expect(hits.single.data.x, x, reason: '$label of cell ($x,$y)');
            expect(hits.single.data.y, y, reason: '$label of cell ($x,$y)');
          });
        }
      }
    });

    test('shared cell boundaries never produce a double hit', () {
      // Exactly on the vertical and horizontal grid lines, and on the
      // four-way corners where four cells meet.
      for (var i = 1; i < 8; i++) {
        for (var j = 1; j < 8; j++) {
          for (final p in [
            Vector2(i * kCell, (j + 0.5) * kCell),
            Vector2((i + 0.5) * kCell, j * kCell),
            Vector2(i * kCell, j * kCell),
          ]) {
            expect(_hits(nodes, p).length, 1, reason: 'boundary point $p');
          }
        }
      }
    });

    test('a sparse board leaves genuine gaps unclaimed', () {
      final sparse = [_nodeAt(0, 0), _nodeAt(5, 5)];
      expect(_hits(sparse, Vector2(2.5 * kCell, 2.5 * kCell)), isEmpty);
      expect(_hits(sparse, Vector2(0.5 * kCell, 0.5 * kCell)).length, 1);
    });
  });
}
