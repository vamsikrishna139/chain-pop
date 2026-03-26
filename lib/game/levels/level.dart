enum Direction {
  up, down, left, right
}

class NodeData {
  final int id;
  int x;
  int y;
  final Direction dir;

  NodeData({
    required this.id,
    required this.x,
    required this.y,
    required this.dir,
  });

  NodeData clone() {
    return NodeData(id: id, x: x, y: y, dir: dir);
  }
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

// Hardcoded mock levels
class LevelManager {
  static final List<LevelData> levels = [
    // Level 1: Simple intro
    LevelData(
      levelId: 1,
      gridWidth: 3,
      gridHeight: 3,
      nodes: [
        NodeData(id: 1, x: 1, y: 1, dir: Direction.up),    // Top middle
        NodeData(id: 2, x: 1, y: 2, dir: Direction.down),  // Bottom middle
      ],
    ),
    // Level 2: Chain reaction / blocking
    LevelData(
      levelId: 2,
      gridWidth: 4,
      gridHeight: 4,
      nodes: [
        NodeData(id: 1, x: 2, y: 2, dir: Direction.left),  // Blocked by 2
        NodeData(id: 2, x: 1, y: 2, dir: Direction.up),    // Free
        NodeData(id: 3, x: 2, y: 1, dir: Direction.right), // Free
      ],
    ),
    // Level 3: A loop or deeper chain
    LevelData(
      levelId: 3,
      gridWidth: 5,
      gridHeight: 5,
      nodes: [
        NodeData(id: 1, x: 2, y: 1, dir: Direction.down),  // Blocked by 2
        NodeData(id: 2, x: 2, y: 2, dir: Direction.right), // Blocked by 4
        NodeData(id: 3, x: 1, y: 2, dir: Direction.right), // Blocked by 2
        NodeData(id: 4, x: 3, y: 2, dir: Direction.down),  // Free
        NodeData(id: 5, x: 2, y: 3, dir: Direction.left),  // Free
      ],
    ),
  ];

  static LevelData? getLevel(int levelId) {
    if (levelId > levels.length) {
      // Loop or return null
      return levels.last;
    }
    return levels.firstWhere((lvl) => lvl.levelId == levelId);
  }
}
