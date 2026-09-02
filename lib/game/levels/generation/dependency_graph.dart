import 'dart:math';

import '../grid_cell_key.dart';
import '../level.dart';
import 'metrics.dart';
import 'retrograde_placement.dart';

/// Ray-dependency DAG extracted from a board or retrograde placement order.
///
/// Exposes topology metrics used by analytics, evaluator soft bands, and
/// retrograde direction reassignment scoring.
class DependencyGraph {
  /// Nodes with no ray blocker (= opening / wave-zero width).
  final int leafCount;

  /// Longest prerequisite chain along ray-block edges.
  final int criticalPathLength;

  /// Widest parallel-removal wave (maximum antichain width).
  final int maxAntichainWidth;

  /// Nodes with fan-in ≥ 2 (shared choke / hub points).
  final int chokePointCount;

  /// Maximum fan-in across all nodes.
  final int maxHubInDegree;

  final Map<int, int> _chainDepth;
  final Map<int, int> _blockerFanIn;
  final Set<int> _blockedIds;

  const DependencyGraph({
    required this.leafCount,
    required this.criticalPathLength,
    required this.maxAntichainWidth,
    required this.chokePointCount,
    required this.maxHubInDegree,
    required Map<int, int> chainDepth,
    required Map<int, int> blockerFanIn,
    required Set<int> blockedIds,
  })  : _chainDepth = chainDepth,
        _blockerFanIn = blockerFanIn,
        _blockedIds = blockedIds;

  int chainDepthOf(int id) => _chainDepth[id] ?? 1;

  int blockerFanInOf(int id) => _blockerFanIn[id] ?? 0;

  bool isBlocked(int id) => _blockedIds.contains(id);

  /// Builds the graph from a shipped [LevelData] board.
  factory DependencyGraph.fromLevel(LevelData level) {
    if (level.nodes.isEmpty) {
      return DependencyGraph._empty();
    }

    final positionToId = <int, int>{
      for (final n in level.nodes) gridCellKey(n.x, n.y): n.id,
    };
    final ids = level.nodes.map((n) => n.id).toList()..sort();
    final rayTarget = <int, int?>{};
    final blockerFanIn = <int, int>{};
    final blockedIds = <int>{};
    final chainDepth = <int, int>{};

    for (final id in ids) {
      final n = level.nodes.firstWhere((node) => node.id == id);
      final target = _firstRayTargetId(n, positionToId, level);
      rayTarget[id] = target;
      if (target != null) {
        blockerFanIn[target] = (blockerFanIn[target] ?? 0) + 1;
        blockedIds.add(id);
      }
    }

    var maxDepth = 0;
    for (final id in ids) {
      final target = rayTarget[id];
      var depth = 1;
      if (target != null) {
        final parentDepth = chainDepth[target] ?? 1;
        if (parentDepth + 1 > depth) depth = parentDepth + 1;
      }
      chainDepth[id] = depth;
      if (depth > maxDepth) maxDepth = depth;
    }

    var maxHub = 0;
    var chokePoints = 0;
    for (final count in blockerFanIn.values) {
      if (count > maxHub) maxHub = count;
      if (count >= 2) chokePoints++;
    }

    final leaves = ids.where((id) => rayTarget[id] == null).length;
    final waveProfile = computeWavePeelingProfile(level);
    final maxAntichain = waveProfile.isEmpty ? leaves : waveProfile.reduce(max);

    return DependencyGraph(
      leafCount: leaves,
      criticalPathLength: maxDepth,
      maxAntichainWidth: maxAntichain,
      chokePointCount: chokePoints,
      maxHubInDegree: maxHub,
      chainDepth: chainDepth,
      blockerFanIn: blockerFanIn,
      blockedIds: blockedIds,
    );
  }

  /// Builds the graph from a retrograde placement order (index = node id).
  factory DependencyGraph.fromRetrogradeOrder(
    List<RetrogradePlacement> order, {
    required int gridWidth,
    required int gridHeight,
  }) {
    if (order.isEmpty) {
      return DependencyGraph._empty();
    }

    final rayTarget = <int, int?>{};
    final blockerFanIn = <int, int>{};
    final blockedIds = <int>{};
    final chainDepth = <int, int>{};

    for (var i = 0; i < order.length; i++) {
      final target = _firstNodeIdOnRetrogradeRay(
        order[i].position,
        order[i].direction,
        order,
        selfId: i,
        gridWidth: gridWidth,
        gridHeight: gridHeight,
      );
      rayTarget[i] = target;
      if (target != null && target < i) {
        blockerFanIn[target] = (blockerFanIn[target] ?? 0) + 1;
        blockedIds.add(i);
      }
    }

    var maxDepth = 0;
    for (var i = 0; i < order.length; i++) {
      final target = rayTarget[i];
      var depth = 1;
      if (target != null && target < i) {
        final parentDepth = chainDepth[target] ?? 1;
        if (parentDepth + 1 > depth) depth = parentDepth + 1;
      }
      chainDepth[i] = depth;
      if (depth > maxDepth) maxDepth = depth;
    }

    var maxHub = 0;
    var chokePoints = 0;
    for (final count in blockerFanIn.values) {
      if (count > maxHub) maxHub = count;
      if (count >= 2) chokePoints++;
    }

    final leaves = rayTarget.entries.where((e) => e.value == null).length;

    final nodes = <NodeData>[
      for (var i = 0; i < order.length; i++)
        NodeData(
          id: i,
          x: order[i].position.x,
          y: order[i].position.y,
          dir: order[i].direction,
        ),
    ];
    final level = LevelData(
      levelId: 0,
      gridWidth: gridWidth,
      gridHeight: gridHeight,
      nodes: nodes,
    );
    final waveProfile = computeWavePeelingProfile(level);
    final maxAntichain = waveProfile.isEmpty ? leaves : waveProfile.reduce(max);

    return DependencyGraph(
      leafCount: leaves,
      criticalPathLength: maxDepth,
      maxAntichainWidth: maxAntichain,
      chokePointCount: chokePoints,
      maxHubInDegree: maxHub,
      chainDepth: chainDepth,
      blockerFanIn: blockerFanIn,
      blockedIds: blockedIds,
    );
  }

  static DependencyGraph _empty() {
    return const DependencyGraph(
      leafCount: 0,
      criticalPathLength: 0,
      maxAntichainWidth: 0,
      chokePointCount: 0,
      maxHubInDegree: 0,
      chainDepth: {},
      blockerFanIn: {},
      blockedIds: {},
    );
  }
}

int? _firstRayTargetId(
  NodeData node,
  Map<int, int> positionToId,
  LevelData level,
) {
  var x = node.x;
  var y = node.y;
  while (true) {
    switch (node.dir) {
      case Direction.up:
        y--;
      case Direction.down:
        y++;
      case Direction.left:
        x--;
      case Direction.right:
        x++;
    }
    if (x < 0 || x >= level.gridWidth || y < 0 || y >= level.gridHeight) {
      return null;
    }
    final hit = positionToId[gridCellKey(x, y)];
    if (hit != null) return hit;
  }
}

int? _firstNodeIdOnRetrogradeRay(
  Point<int> from,
  Direction dir,
  List<RetrogradePlacement> order, {
  required int selfId,
  required int gridWidth,
  required int gridHeight,
}) {
  final keyToId = <int, int>{
    for (var i = 0; i < order.length; i++)
      gridCellKey(order[i].position.x, order[i].position.y): i,
  };
  var x = from.x;
  var y = from.y;
  while (true) {
    switch (dir) {
      case Direction.up:
        y--;
      case Direction.down:
        y++;
      case Direction.left:
        x--;
      case Direction.right:
        x++;
    }
    if (x < 0 || x >= gridWidth || y < 0 || y >= gridHeight) return null;
    final hit = keyToId[gridCellKey(x, y)];
    if (hit != null) return hit == selfId ? null : hit;
  }
}
