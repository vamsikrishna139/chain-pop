import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

enum Direction { up, down, left, right }

/// Immutable data for a single board node.
///
/// [x] and [y] are `final` — grid coordinates never change after placement.
class NodeData {
  final int id;
  final int x;
  final int y;
  final Direction dir;
  final Color color;

  NodeData({
    required this.id,
    required this.x,
    required this.y,
    required this.dir,
    this.color = AppColors.nodeDefault,
  });

  NodeData clone() => NodeData(id: id, x: x, y: y, dir: dir, color: color);

  @override
  String toString() => 'Node($id, at: $x,$y, dir: $dir)';
}

class LevelData {
  final int levelId;
  final int gridWidth;
  final int gridHeight;

  /// When non-null and non-empty, only these `"x,y"` cells may hold nodes
  /// (irregular silhouette). Blocking rays still use straight lines across the
  /// full `gridWidth`×`gridHeight` bounds. When null, every cell may hold a node.
  final Set<String>? playCells;

  final List<NodeData> nodes;

  LevelData({
    required this.levelId,
    required this.gridWidth,
    required this.gridHeight,
    required this.nodes,
    this.playCells,
  });
}
