import 'dart:math' show log;

import '../../game/levels/generation/difficulty_mode.dart';

/// Movement-tutorial steps (indices 0–3) and the mechanic intros (cores,
/// relay, locked — indices 5+): generous **60s** each.
const int tutorialCountdownEarlySec = 60;

/// Movement recap (index 4): short but forgiving (**45s**).
const int tutorialCountdownFinalSec = 45;

/// Graduation board (index 9): eight arrows spanning all five types across two
/// phase acts, so it needs more room to read than a single-mechanic intro.
const int tutorialCountdownGraduationSec = 90;

/// Campaign Easy countdown ceiling (four minutes).
const int easyCampaignTimerCapSeconds = 240;

/// Seconds contributed per populated cell before cushions / scaling on Easy campaign.
const double easyCampaignBaseSecondsPerNode = 20;

/// Flat cushion added before difficulty scales on Easy campaign.
const double easyCampaignTimerCushionSeconds = 90;

/// Minimum Easy campaign countdown floor (seconds).
const int easyCampaignTimerFloorSeconds = 120;

/// Per-level pacing factor on Easy: `1 − slope × levelId`, clamped (mirrors softer boards in [DifficultyParameters] for early levels).
const double easyCampaignTimerLevelSlope = 0.0012;
const double easyCampaignTimerLevelClampLow = 0.82;

/// Medium: base seconds multiplier per populated node (`α` in HUD docstring).
/// The **30** ceiling pairs with dense [DifficultyParameters] Medium layouts.
const double mediumCampaignTimerBasePerNode = 4.0;
const double mediumCampaignTimerLogFactor = 0.18;
const double mediumCampaignTimerLevelSlope = 0.008;
const double mediumCampaignTimerLevelClampLow = 0.75;
const int mediumCampaignTimerClampLowSec = 45;
const int mediumCampaignTimerClampHighSec = 180;

/// Hard: tighter base factor for expert boards ([DifficultyParameters] allows up to 60 nodes).
const double hardCampaignTimerBasePerNode = 2.8;
const double hardCampaignTimerLogFactor = 0.12;
const double hardCampaignTimerLevelSlope = 0.004;
const double hardCampaignTimerLevelClampLow = 0.60;
const int hardCampaignTimerClampLowSec = 25;
const int hardCampaignTimerClampHighSec = 150;

/// Virtual level index for daily puzzles — stabilizes pacing vs calendar keys.
const int dailyChallengeVirtualLevelIndex = 40;

/// Onboarding steps use [tutorialCountdownEarlySec], except the movement recap
/// (index 4) on [tutorialCountdownFinalSec] and the all-types graduation board
/// (index 9) on [tutorialCountdownGraduationSec].
int computeTutorialCountdownSec(int tutorialIndex) => switch (tutorialIndex) {
      4 => tutorialCountdownFinalSec,
      9 => tutorialCountdownGraduationSec,
      _ => tutorialCountdownEarlySec,
    };

/// Per-mode **countdown** seconds (time runs **down** to zero in [GameScreen]).
///
/// **Easy:** generous limit from node count + level (was untimed / elapsed-only
/// before; now uses the same countdown HUD as other modes). Capped at
/// [easyCampaignTimerCapSeconds] so late-game boards stay bounded.
///
/// **Medium / Hard:** T(mode, N, L) = α × N × (1 + β × ln N) × max(γ_min, 1 − δ × L).
/// Coefficients are tuned next to [DifficultyParameters] node density per mode.
int? computeGameTimeLimit(
  DifficultyMode mode,
  int nodeCount,
  int levelId,
) {
  switch (mode) {
    case DifficultyMode.easy:
      final n = nodeCount.clamp(1, 999);
      final perNode = easyCampaignBaseSecondsPerNode * n;
      final levelScale = (1.0 - easyCampaignTimerLevelSlope * levelId).clamp(
        easyCampaignTimerLevelClampLow,
        1.0,
      );
      final raw = (perNode + easyCampaignTimerCushionSeconds) * levelScale;
      return raw
          .round()
          .clamp(easyCampaignTimerFloorSeconds, easyCampaignTimerCapSeconds);
    case DifficultyMode.medium:
      final n = nodeCount.clamp(1, 999);
      final base = mediumCampaignTimerBasePerNode *
          n *
          (1 + mediumCampaignTimerLogFactor * log(n));
      final learning = (1.0 - mediumCampaignTimerLevelSlope * levelId).clamp(
        mediumCampaignTimerLevelClampLow,
        1.0,
      );
      return (base * learning).round().clamp(
          mediumCampaignTimerClampLowSec, mediumCampaignTimerClampHighSec);
    case DifficultyMode.hard:
      final n = nodeCount.clamp(1, 999);
      final base = hardCampaignTimerBasePerNode *
          n *
          (1 + hardCampaignTimerLogFactor * log(n));
      final learning = (1.0 - hardCampaignTimerLevelSlope * levelId).clamp(
        hardCampaignTimerLevelClampLow,
        1.0,
      );
      return (base * learning)
          .round()
          .clamp(hardCampaignTimerClampLowSec, hardCampaignTimerClampHighSec);
  }
}

/// Daily puzzles use medium pacing with a fixed virtual level index so the
/// timer does not shrink as [dayKey] grows.
int? computeDailyChallengeTimeLimit(int nodeCount) {
  return computeGameTimeLimit(
    DifficultyMode.medium,
    nodeCount,
    dailyChallengeVirtualLevelIndex,
  );
}
