import 'level.dart';

class LevelSolver {
  /// Returns true if the level can be fully cleared.
  static bool isSolvable(LevelData level) {
    List<NodeData> currentNodes = level.nodes.map((n) => n.clone()).toList();
    bool changed = true;

    while (changed && currentNodes.isNotEmpty) {
      changed = false;
      for (int i = 0; i < currentNodes.length; i++) {
        if (canRemove(currentNodes[i], currentNodes)) {
          currentNodes.removeAt(i);
          changed = true;
          break; // Start over from the new list
        }
      }
    }

    return currentNodes.isEmpty;
  }

  /// Finds a node that can be currently removed.
  static NodeData? getHint(List<NodeData> activeNodes) {
    for (var node in activeNodes) {
      if (canRemove(node, activeNodes)) {
        return node;
      }
    }
    return null;
  }

  static bool canRemove(NodeData node, List<NodeData> allNodes) {
    for (var other in allNodes) {
      if (other.id == node.id) continue;

      switch (node.dir) {
        case Direction.up:
          if (other.x == node.x && other.y < node.y) return false;
          break;
        case Direction.down:
          if (other.x == node.x && other.y > node.y) return false;
          break;
        case Direction.left:
          if (other.y == node.y && other.x < node.x) return false;
          break;
        case Direction.right:
          if (other.y == node.y && other.x > node.x) return false;
          break;
      }
    }
    return true;
  }
}
