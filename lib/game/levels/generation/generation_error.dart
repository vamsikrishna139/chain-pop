/// Represents errors that can occur during level generation.
///
/// Provides factory constructors for different error types to enable
/// structured error handling and reporting.
///
/// Example usage:
/// ```dart
/// return Result.error(
///   GenerationError.invalidConfiguration('Grid size must be at least 3x3')
/// );
/// ```
class GenerationError {
  /// The type of error that occurred.
  final String type;

  /// A descriptive message explaining the error.
  final String message;

  /// Private constructor for creating errors.
  GenerationError._(this.type, this.message);

  /// Creates an error for invalid configuration parameters.
  ///
  /// Used when the provided [LevelConfiguration] fails validation.
  factory GenerationError.invalidConfiguration(String message) {
    return GenerationError._('invalid_configuration', message);
  }

  /// Creates an error when no valid directions can be assigned to nodes.
  ///
  /// This typically occurs in highly constrained scenarios where the
  /// backward generation algorithm cannot find valid node directions.
  factory GenerationError.noValidDirections(String message) {
    return GenerationError._('no_valid_directions', message);
  }

  /// Creates an error for unexpected failures during generation.
  ///
  /// Used for catching and wrapping unexpected exceptions.
  factory GenerationError.unexpected(String message) {
    return GenerationError._('unexpected', message);
  }

  /// Greedy elimination exhausted every randomized elimination trial — the
  /// `tryGreedyEliminationOrder` contract returns null honestly (no shuffle
  /// fallback order).
  factory GenerationError.greedyEliminationExhausted([String detail = '']) {
    return GenerationError._(
      'greedy_elimination_exhausted',
      detail.isEmpty ? 'Greedy elimination exhausted' : detail,
    );
  }

  /// Legacy greedy path could not assign backward-safe directions after a
  /// valid elimination order was found.
  factory GenerationError.greedyDirectionAssignmentFailed(
      [String detail = '']) {
    return GenerationError._(
      'greedy_direction_assignment_failed',
      detail.isEmpty
          ? 'Greedy direction assignment failed'
          : detail,
    );
  }

  @override
  String toString() => 'GenerationError($type): $message';
}
