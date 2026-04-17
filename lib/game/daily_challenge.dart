/// Local-calendar daily puzzle (same layout for all players on a given date).
class DailyChallenge {
  DailyChallenge._();

  /// Local calendar day as `YYYYMMDD` (e.g. `20260412`).
  static int dateKeyLocal(DateTime when) {
    final t = DateTime(when.year, when.month, when.day);
    return t.year * 10000 + t.month * 100 + t.day;
  }

  /// Short label for HUD / win sheet (no extra packages).
  static String compactDateLabel(DateTime when) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final m = months[when.month - 1];
    return '$m ${when.day}, ${when.year}';
  }

  /// [compactDateLabel] for a [dateKeyLocal] value.
  static String compactDateLabelFromKey(int dayKey) {
    final y = dayKey ~/ 10000;
    final m = (dayKey ~/ 100) % 100;
    final d = dayKey % 100;
    return compactDateLabel(DateTime(y, m, d));
  }

  /// App bar style, e.g. `Apr 2026`.
  static String monthYearTitle(int year, int month) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[month - 1]} $year';
  }
}
