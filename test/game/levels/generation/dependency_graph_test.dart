import 'dart:math';

import 'package:chain_pop/game/levels/generation/dependency_graph.dart';
import 'package:chain_pop/game/levels/generation/metrics.dart';
import 'package:chain_pop/game/levels/generation/retrograde_placement.dart';
import 'package:chain_pop/game/levels/level.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DependencyGraph.fromLevel', () {
    test('linear chain has one leaf and path length equal to node count', () {
      // Point left so higher ids depend on lower ids on the ray.
      final level = LevelData(
        levelId: 0,
        gridWidth: 8,
        gridHeight: 3,
        nodes: [
          for (var i = 0; i < 4; i++)
            NodeData(
              id: i,
              x: i,
              y: 1,
              dir: Direction.left,
            ),
        ],
      );

      final graph = DependencyGraph.fromLevel(level);

      expect(graph.leafCount, equals(1));
      expect(graph.criticalPathLength, equals(4));
      expect(graph.maxHubInDegree, lessThan(2));
      expect(graph.maxAntichainWidth, equals(1));
    });

    test('parallel opening row matches wave-zero width', () {
      final level = LevelData(
        levelId: 0,
        gridWidth: 6,
        gridHeight: 6,
        nodes: [
          for (var i = 0; i < 3; i++)
            NodeData(id: i, x: i, y: 0, dir: Direction.up),
        ],
      );

      final graph = DependencyGraph.fromLevel(level);
      final metrics = LevelMetrics.compute(level);

      expect(graph.leafCount, equals(3));
      expect(graph.leafCount, equals(metrics.waveZeroWidth));
      expect(graph.criticalPathLength, equals(metrics.criticalUnlockDepth));
    });

    test('hub with fan-in 3 counts three choke points at one node', () {
      final level = LevelData(
        levelId: 0,
        gridWidth: 5,
        gridHeight: 5,
        nodes: [
          NodeData(id: 0, x: 2, y: 2, dir: Direction.up),
          NodeData(id: 1, x: 2, y: 3, dir: Direction.down),
          NodeData(id: 2, x: 1, y: 2, dir: Direction.right),
          NodeData(id: 3, x: 3, y: 2, dir: Direction.left),
        ],
      );

      final graph = DependencyGraph.fromLevel(level);

      expect(graph.maxHubInDegree, greaterThanOrEqualTo(2));
      expect(graph.chokePointCount, greaterThanOrEqualTo(1));
    });
  });

  group('DependencyGraph.fromRetrogradeOrder', () {
    test('matches fromLevel for the same placement order', () {
      final order = [
        const RetrogradePlacement(
            position: Point(0, 0), direction: Direction.up),
        const RetrogradePlacement(
            position: Point(1, 0), direction: Direction.up),
        const RetrogradePlacement(
            position: Point(2, 0), direction: Direction.right),
      ];

      final fromOrder = DependencyGraph.fromRetrogradeOrder(
        order,
        gridWidth: 6,
        gridHeight: 6,
      );

      final level = LevelData(
        levelId: 0,
        gridWidth: 6,
        gridHeight: 6,
        nodes: [
          for (var i = 0; i < order.length; i++)
            NodeData(
              id: i,
              x: order[i].position.x,
              y: order[i].position.y,
              dir: order[i].direction,
            ),
        ],
      );
      final fromLevel = DependencyGraph.fromLevel(level);

      expect(fromOrder.leafCount, equals(fromLevel.leafCount));
      expect(
          fromOrder.criticalPathLength, equals(fromLevel.criticalPathLength));
      expect(fromOrder.chokePointCount, equals(fromLevel.chokePointCount));
      expect(fromOrder.maxHubInDegree, equals(fromLevel.maxHubInDegree));
    });
  });
}
