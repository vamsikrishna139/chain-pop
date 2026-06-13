import 'dart:collection';

import 'silhouettes.dart';

/// Tracks recent [SilhouetteVisualFamily] emissions within a generation session
/// and penalizes consecutive geometric-lattice boards in K-loop ranking.
class SilhouetteSessionTracker {
  static const int _historyLength = 5;

  final Queue<SilhouetteVisualFamily> _recent =
      Queue<SilhouetteVisualFamily>();

  /// Records [silhouette] after a level is emitted.
  void record(SilhouetteId silhouette) {
    _recent.add(silhouetteVisualFamily(silhouette));
    while (_recent.length > _historyLength) {
      _recent.removeFirst();
    }
  }

  /// Negative score adjustment for candidates that extend a geometric streak.
  double streakPenalty(SilhouetteId silhouette) {
    final family = silhouetteVisualFamily(silhouette);
    if (family != SilhouetteVisualFamily.geometricLattice) return 0;

    var consecutive = 0;
    for (final past in _recent.toList().reversed) {
      if (past == SilhouetteVisualFamily.geometricLattice) {
        consecutive++;
      } else {
        break;
      }
    }
    if (consecutive < 2) return 0;
    return -2.5 * consecutive;
  }

  /// Boost organic / archipelago / corridor silhouettes when geometric streak ≥ 2.
  double diversityBoost(SilhouetteId silhouette) {
    final family = silhouetteVisualFamily(silhouette);
    if (family == SilhouetteVisualFamily.geometricLattice) return 0;

    var consecutiveGeometric = 0;
    for (final past in _recent.toList().reversed) {
      if (past == SilhouetteVisualFamily.geometricLattice) {
        consecutiveGeometric++;
      } else {
        break;
      }
    }
    if (consecutiveGeometric < 2) return 0;
    return 1.5;
  }

  /// Consecutive geometric-lattice count at session tail (for tests).
  int trailingGeometricStreak() {
    var streak = 0;
    for (final past in _recent.toList().reversed) {
      if (past == SilhouetteVisualFamily.geometricLattice) {
        streak++;
      } else {
        break;
      }
    }
    return streak;
  }
}
