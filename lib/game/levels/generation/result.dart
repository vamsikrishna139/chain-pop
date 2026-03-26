/// Result type for operations that can fail with typed errors.
///
/// This type represents either a successful result containing a value of type [T],
/// or a failure containing an error of type [E].
///
/// Example usage:
/// ```dart
/// Result<LevelData, GenerationError> result = generator.generate(1);
/// if (result.isSuccess) {
///   print('Generated level: ${result.value}');
/// } else {
///   print('Error: ${result.error.message}');
/// }
/// ```
class Result<T, E> {
  final T? _value;
  final E? _error;
  final bool isSuccess;

  /// Creates a successful result containing [value].
  Result.success(T value)
      : _value = value,
        _error = null,
        isSuccess = true;

  /// Creates a failed result containing [error].
  Result.error(E error)
      : _value = null,
        _error = error,
        isSuccess = false;

  /// Returns the success value.
  ///
  /// Throws if this result is an error. Check [isSuccess] before accessing.
  T get value {
    if (!isSuccess) {
      throw StateError('Cannot access value on error result');
    }
    return _value!;
  }

  /// Returns the error value.
  ///
  /// Throws if this result is a success. Check [isSuccess] before accessing.
  E get error {
    if (isSuccess) {
      throw StateError('Cannot access error on success result');
    }
    return _error!;
  }

  /// Returns true if this result represents an error.
  bool get isError => !isSuccess;
}
