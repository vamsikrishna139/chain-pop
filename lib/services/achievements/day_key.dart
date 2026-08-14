/// Calendar arithmetic for `DailyChallenge.dateKeyLocal` keys.
///
/// Those keys are `YYYYMMDD` integers, not day counts, so `key - 1` is not
/// "yesterday" — `20260301 - 1` is `20260300`, which is not a date. Streaks
/// need real calendar math, which is what this provides.
///
/// All conversions go through UTC. Both ends are midnight-anchored calendar
/// dates with no time component, and using UTC keeps a daylight-saving
/// transition from making two adjacent days 23 or 25 hours apart and rounding
/// [daysBetween] to the wrong integer.
abstract final class DayKey {
  DayKey._();

  /// Decodes `YYYYMMDD` into a UTC-midnight [DateTime].
  static DateTime toDate(int dayKey) => DateTime.utc(
        dayKey ~/ 10000,
        (dayKey ~/ 100) % 100,
        dayKey % 100,
      );

  /// Encodes a [DateTime]'s calendar date as `YYYYMMDD`.
  static int fromDate(DateTime when) =>
      when.year * 10000 + when.month * 100 + when.day;

  /// Calendar days from [fromKey] to [toKey]. Negative when [toKey] is earlier.
  static int daysBetween(int fromKey, int toKey) =>
      toDate(toKey).difference(toDate(fromKey)).inDays;

  /// True when [toKey] is the calendar day immediately after [fromKey].
  static bool isNextDay(int fromKey, int toKey) =>
      daysBetween(fromKey, toKey) == 1;

  /// Number of days in the month containing [dayKey].
  static int daysInMonth(int dayKey) {
    final y = dayKey ~/ 10000;
    final m = (dayKey ~/ 100) % 100;
    // Day zero of the following month is the last day of this one.
    return DateTime.utc(m == 12 ? y + 1 : y, m == 12 ? 1 : m + 1, 0).day;
  }

  /// Every `YYYYMMDD` key in the month containing [dayKey], in order.
  static List<int> monthKeys(int dayKey) {
    final base = (dayKey ~/ 100) * 100;
    return <int>[for (var d = 1; d <= daysInMonth(dayKey); d++) base + d];
  }

  /// Rejects values that cannot be a `YYYYMMDD` date. A corrupt or absent key
  /// must not be treated as a real day by streak logic.
  static bool isValid(int dayKey) {
    if (dayKey < 10000101 || dayKey > 99991231) return false;
    final m = (dayKey ~/ 100) % 100;
    final d = dayKey % 100;
    if (m < 1 || m > 12 || d < 1) return false;
    return d <= daysInMonth(dayKey);
  }
}
