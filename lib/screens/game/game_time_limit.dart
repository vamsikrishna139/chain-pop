import 'dart:math' show log;

import '../../game/levels/generation/difficulty_mode.dart';

/// First four tutorial steps (indices 0–3): generous **60s** each.
const int tutorialCountdownEarlySec = 60;

/// Final tutorial recap (index 4): short but forgiving (**45s**).
const int tutorialCountdownFinalSec = 45;

/// Onboarding steps 0–3 use [tutorialCountdownEarlySec]; step 4 uses
/// [tutorialCountdownFinalSec].
int computeTutorialCountdownSec(int tutorialIndex) =>
    tutorialIndex >= 4 ? tutorialCountdownFinalSec : tutorialCountdownEarlySec;

/// Per-mode **countdown** seconds (time runs **down** to zero in [GameScreen]).
///
/// **Easy:** generous limit from node count + level (was untimed / elapsed-only
/// before; now uses the same countdown HUD as other modes). Capped at **4
/// minutes** so late-game boards stay bounded.
///
/// Medium / Hard: T(mode, N, L) = α × N × (1 + β × ln N) × max(γ_min, 1 − δ × L)
int? computeGameTimeLimit(
  DifficultyMode mode,
  int nodeCount,
  int levelId,
) {
  switch (mode) {
    case DifficultyMode.easy:
      final n = nodeCount.clamp(1, 999);
      // Generous: ~20s per arrow + 90s cushion; eases down slightly on deep levels.
      const easyMaxSec = 240; // 4 minutes
      final perNode = 20.0 * n;
      const cushion = 90.0;
      final levelScale = (1.0 - 0.0012 * levelId).clamp(0.82, 1.0);
      final raw = (perNode + cushion) * levelScale;
      return raw.round().clamp(120, easyMaxSec);
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
