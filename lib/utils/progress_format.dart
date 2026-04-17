import '../game/levels/level_grid_config.dart';
import '../game/levels/generation/difficulty_mode.dart';
import '../services/storage_service.dart';

/// Human-readable numbers and stretch bands for high-level players (1000+).
abstract final class ProgressFormat {
  ProgressFormat._();

  /// "1,018" — stable width, scales to any int.
  static String level(int n) {
    if (n <= 0) return '0';
    final s = n.toString();
    final buf = StringBuffer();
    final lead = s.length % 3;
    if (lead > 0) {
      buf.write(s.substring(0, lead));
    }
    for (var i = lead; i < s.length; i += 3) {
      if (buf.isNotEmpty) buf.write(',');
      buf.write(s.substring(i, i + 3));
    }
    return buf.toString();
  }

  /// Short star counts for tight tiles (e.g. "2.9k", "847").
  static String starsCompact(int n) {
    if (n < 0) return '0';
    if (n < 1000) return level(n);
    if (n < 1000000) {
      final k = n / 1000;
      final rounded = (k * 10).round() / 10;
      if (rounded == rounded.roundToDouble()) {
        return '${rounded.toInt()}k';
      }
      return '${rounded}k';
    }
    final m = n / 1000000;
    final rounded = (m * 10).round() / 10;
    if (rounded == rounded.roundToDouble()) {
      return '${rounded.toInt()}M';
    }
    return '${rounded}M';
  }

  /// Average stars per stage cleared (0…3). Returns null if no levels.
  static double? avgStarsPerClearedStage(int totalStars, int frontier) {
    if (frontier <= 0) return null;
    return (totalStars / frontier).clamp(0.0, 3.0);
  }

  /// The 20-level window that contains [frontier], aligned with the level grid.
  static ({int start, int end}) stretchWindow(int frontier) {
    if (frontier < 1) return (start: 1, end: kLevelsPerGridPage);
    final idx = (frontier - 1) ~/ kLevelsPerGridPage;
    final start = idx * kLevelsPerGridPage + 1;
    final end = start + kLevelsPerGridPage - 1;
    return (start: start, end: end);
  }

  /// Stars earned on [start…frontier] and max possible (3 per cleared stage in range).
  static ({int earned, int cap}) stretchStars(
    DifficultyMode mode,
    int frontier,
  ) {
    if (frontier < 1) return (earned: 0, cap: 3);
    final w = stretchWindow(frontier);
    final earned = StorageService.totalStarsInRange(mode, w.start, frontier);
    final clearedInStretch = frontier - w.start + 1;
    final cap = 3 * clearedInStretch;
    return (earned: earned, cap: cap.clamp(3, 3 * kLevelsPerGridPage));
  }
}
