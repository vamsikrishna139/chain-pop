/// Represents the result of a validation operation.
///
/// Contains a boolean indicating validity and an optional message
/// providing details about validation failures.
///
/// Example usage:
/// ```dart
/// ValidationResult result = config.validate();
/// if (!result.isValid) {
///   print('Validation failed: ${result.message}');
/// }
/// ```
class ValidationResult {
  /// Whether the validation passed.
  final bool isValid;

  /// Descriptive message, typically populated for validation failures.
  final String message;

  /// Creates a successful validation result.
  ValidationResult.success()
      : isValid = true,
        message = '';

  /// Creates a failed validation result with the given error [message].
  ValidationResult.error(this.message) : isValid = false;
}
