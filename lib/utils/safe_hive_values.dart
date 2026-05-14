// Coercion helpers for Hive reads so a bad or legacy-typed cell does not
// crash the app (local-only game state; not a substitute for encryption).

/// Normalizes dynamic Hive values to [bool] for settings-style flags.
bool coerceHiveBool(Object? value, {required bool fallback}) {
  if (value is bool) return value;
  if (value is int) return value != 0;
  if (value is num) return value != 0;
  if (value is String) {
    switch (value.toLowerCase()) {
      case 'true':
      case '1':
      case 'yes':
        return true;
      case 'false':
      case '0':
      case 'no':
        return false;
    }
  }
  return fallback;
}

/// Normalizes dynamic Hive values to [int], then clamps to \[min, max\].
int coerceHiveInt(
  Object? value, {
  required int fallback,
  int min = -0x7fffffff,
  int max = 0x7fffffff,
}) {
  int n;
  if (value == null) {
    return fallback;
  } else if (value is int) {
    n = value;
  } else if (value is num) {
    n = value.round();
  } else if (value is String) {
    n = int.tryParse(value.trim()) ?? fallback;
  } else {
    return fallback;
  }
  if (n < min) return min;
  if (n > max) return max;
  return n;
}
