import 'dart:math' show log;

import '../../game/levels/generation/difficulty_mode.dart';

/// Per-mode countdown seconds for Medium / Hard. Easy returns `null` (untimed).
///
/// T(mode, N, L) = α × N × (1 + β × ln N) × max(γ_min, 1 − δ × L)
int? computeGameTimeLimit(
  DifficultyMode mode,
  int nodeCount,
  int levelId,
) {
  switch (mode) {
    case DifficultyMode.easy:
      return null;
    case DifficultyMode.medium:
      final n = nodeCount.clamp(1, 999);
      final base = 4.0 * n * (1 + 0.18 * log(n));
      final learning = (1.0 - 0.008 * levelId).clamp(0.75, 1.0);
      return (base * learning).round().clamp(45, 180);
    case DifficultyMode.hard:
      final n = nodeCount.clamp(1, 999);
      final base = 2.8 * n * (1 + 0.12 * log(n));
      final learning = (1.0 - 0.004 * levelId).clamp(0.60, 1.0);
      return (base * learning).round().clamp(25, 150);
  }
}

/// Daily puzzles use medium pacing with a fixed virtual level index so the
/// timer does not shrink as [dayKey] grows.
int? computeDailyChallengeTimeLimit(int nodeCount) {
  return computeGameTimeLimit(DifficultyMode.medium, nodeCount, 40);
}
