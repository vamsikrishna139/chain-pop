import '../../game/levels/generation/difficulty_mode.dart';
import '../session_campaign_streak.dart';
import '../storage_service.dart';
import 'ad_placements.dart';
import 'ad_service.dart';
import 'ad_debug_log.dart';
import 'campaign_interstitial_frustration_gate.dart';

/// Campaign-only between-level interstitial (see [SessionCampaignStreak]).
abstract final class CampaignBetweenLevelsAds {
  CampaignBetweenLevelsAds._();

  /// Presents [AdPlacements.betweenLevelsStreak] when the session streak threshold
  /// is met. Resets the streak only after a successful presentation.
  ///
  /// Returns `true` iff [AdService.showInterstitialIfReady] returned `true`.
  ///
  /// [ignoreEngagementGates] skips lifetime onboarding thresholds and tilt
  /// suppression (**tests only**; production always uses `false`).
  static Future<bool> maybePresentForCampaignTransition({
    required AdService ads,
    required DifficultyMode difficulty,
    required bool isTutorial,
    required bool isDailyChallenge,
    bool ignoreEngagementGates = false,
  }) async {
    final campaignLevel = !isTutorial && !isDailyChallenge;
    final need = SessionCampaignStreak.interstitialStreakThreshold(difficulty);
    if (!campaignLevel || SessionCampaignStreak.wins < need) {
      return false;
    }
    if (!ignoreEngagementGates) {
      if (!StorageService.campaignInterstitialLifetimeGateSatisfied) {
        adDebug(
          'between-levels: skip (lifetime gate not satisfied)',
        );
        return false;
      }
      if (CampaignInterstitialFrustrationGate.shouldSuppressInterstitial()) {
        adDebug('between-levels: skip (frustration gate)');
        return false;
      }
    }
    adDebug(
      'between-levels: presenting (wins=${SessionCampaignStreak.wins}/$need)',
    );
    final shown = await ads.showInterstitialIfReady(
      placement: AdPlacements.betweenLevelsStreak,
    );
    if (shown) SessionCampaignStreak.reset();
    return shown;
  }
}
