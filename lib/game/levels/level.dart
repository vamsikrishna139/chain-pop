import 'package:flutter/material.dart';

enum Direction { up, down, left, right }

class NodeData {
  final int id;
  int x;
  int y;
  final Direction dir;
  final Color color;

  NodeData({
    required this.id,
    required this.x,
    required this.y,
    required this.dir,
    this.color = const Color(0xFF4FACFE),
  });

  NodeData clone() {
    return NodeData(id: id, x: x, y: y, dir: dir, color: color);
  }

  @override
  String toString() => 'Node($id, at: $x,$y, dir: $dir)';
}

class LevelData {
  final int levelId;
  final int gridWidth;
  final int gridHeight;
  final List<NodeData> nodes;

  LevelData({
    required this.levelId,
    required this.gridWidth,
    required this.gridHeight,
    required this.nodes,
  });
}
