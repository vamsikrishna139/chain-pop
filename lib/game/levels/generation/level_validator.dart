import '../level.dart';
import 'validation_result.dart';

/// Validates that generated levels are solvable by simulating the solution path.
///
/// The validator verifies that nodes can be removed in ID order (0, 1, 2, ...)
/// by checking that each node's direction is clear when its turn arrives.
///
/// Example usage:
/// ```dart
/// final validator = LevelValidator();
/// final result = validator.validate(level);
/// if (!result.isValid) {
///   print('Level is not solvable: ${result.message}');
/// }
/// ```
class LevelValidator {
  /// Validates that a level is solvable by simulating the solution path.
  ///
  /// The method simulates removing nodes in ID order (0, 1, 2, ...) and
  /// verifies that each node can be removed when its turn arrives.
  ///
  /// Returns [ValidationResult.success] if the level is solvable,
  /// or [ValidationResult.error] with a descriptive message if validation fails.
  ValidationResult validate(LevelData level) {
    // Sort nodes by ID to get solution path order
    final sortedNodes = List<NodeData>.from(level.nodes)
      ..sort((a, b) => a.id.compareTo(b.id));

    // Clone all nodes to simulate removal
    List<NodeData> remainingNodes = level.nodes.map((n) => n.clone()).toList();

    // Simulate removing each node in solution path order
    for (final nodeToRemove in sortedNodes) {
      // Check if this node can be removed
      if (!_canRemoveNode(nodeToRemove, remainingNodes)) {
        return ValidationResult.error(
          'Node ${nodeToRemove.id} at (${nodeToRemove.x}, ${nodeToRemove.y}) '
          'cannot be removed at step ${nodeToRemove.id}',
        );
      }

      // Remove the node from remaining nodes
      remainingNodes.removeWhere((n) => n.id == nodeToRemove.id);
    }

    // Verify all nodes were removed
    if (remainingNodes.isNotEmpty) {
      return ValidationResult.error(
        'Validation completed but ${remainingNodes.length} nodes remain',
      );
    }

    return ValidationResult.success();
  }

  /// Checks if a node can be removed given the current board state.
  ///
  /// A node can be removed if no other nodes block its direction.
  /// For example, a node pointing up can be removed if there are no
  /// other nodes directly above it.
  ///
  /// Returns true if the node can be removed, false otherwise.
  bool _canRemoveNode(NodeData node, List<NodeData> allNodes) {
    for (final other in allNodes) {
      // Skip the node itself
      if (other.id == node.id) continue;

      // Check if other node blocks this node's direction
      switch (node.dir) {
        case Direction.up:
          // Another node blocks if it's in the same column and above
          if (other.x == node.x && other.y < node.y) return false;
          break;
        case Direction.down:
          // Another node blocks if it's in the same column and below
          if (other.x == node.x && other.y > node.y) return false;
          break;
        case Direction.left:
          // Another node blocks if it's in the same row and to the left
          if (other.y == node.y && other.x < node.x) return false;
          break;
        case Direction.right:
          // Another node blocks if it's in the same row and to the right
          if (other.y == node.y && other.x > node.x) return false;
          break;
      }
    }

    return true;
  }
}
