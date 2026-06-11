import '../level.dart';
import '../level_solver.dart';
import 'validation_result.dart';

/// Validates that generated levels are solvable by simulating the solution path.
///
/// The validator verifies that nodes can be removed in ID order (0, 1, 2, ...)
/// by checking that each node's direction is clear when its turn arrives.
/// Relay pops are simulated with the same row rotation gameplay applies, so a
/// level only validates if its canonical solution survives the rotation.
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
    // Solution path order is ID order (0, 1, 2, ...)
    final orderedIds = level.nodes.map((n) => n.id).toList()..sort();

    // Clone all nodes to simulate removal. Relay rotations mutate directions
    // mid-simulation, so each step must re-read the node from this list
    // rather than trust the original snapshot.
    List<NodeData> remainingNodes = level.nodes.map((n) => n.clone()).toList();

    // Simulate removing each node in solution path order
    for (final id in orderedIds) {
      final nodeToRemove = remainingNodes.firstWhere((n) => n.id == id);
      if (!LevelSolver.canRemove(nodeToRemove, remainingNodes, level)) {
        return ValidationResult.error(
          'Node ${nodeToRemove.id} at (${nodeToRemove.x}, ${nodeToRemove.y}) '
          'cannot be removed at step ${nodeToRemove.id}',
        );
      }

      // Mirror gameplay: popping a relay rotates its whole row clockwise.
      if (nodeToRemove.kind == NodeKind.relay) {
        remainingNodes = [
          for (final n in remainingNodes)
            n.y == nodeToRemove.y ? n.copyWith(dir: n.dir.rotatedCw) : n,
        ];
      }

      remainingNodes.removeWhere((n) => n.id == id);
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
