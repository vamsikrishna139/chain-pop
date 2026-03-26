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

  @override
  String toString() => 'GenerationError($type): $message';
}
