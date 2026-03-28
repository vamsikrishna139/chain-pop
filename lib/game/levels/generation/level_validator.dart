import '../level.dart';
import '../level_solver.dart';
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
      if (!LevelSolver.canRemove(nodeToRemove, remainingNodes, level)) {
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
}
