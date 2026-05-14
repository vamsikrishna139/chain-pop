import 'package:flutter/widgets.dart';

/// Mediates rewarded and interstitial ads without pulling ad SDK types into gameplay code.
///
/// Phase 2: Before production rollout in EEA/UK, integrate UMP (User Messaging Platform)
/// for consent, and defer Mobile Ads SDK initialization / first load until after the
/// consent flow — see Google's "Get started" / GDPR guidance for Flutter.
abstract class AdService {
  /// One-time SDK startup + background loads (safe to call multiple times).
  Future<void> bootstrap();

  /// Optional hook so UI can rebuild when preload completes or ads are disposed.
  void setInventoryListener(void Function()? onChanged);

  /// Removes [listener] only if it is still the active callback from [setInventoryListener].
  ///
  /// Call from a screen's [State.dispose] after [Navigator.pushReplacement]: the new route
  /// may register first; clearing unconditionally would drop the new listener.
  void clearInventoryListenerIfSame(void Function()? listener);

  /// Whether a rewarded placement has a loaded ad (controls dialog affordances).
  bool isRewardedReady(String placement);

  /// Fire-and-forget preload for [placement] (see [AdPlacements]).
  Future<void> preloadRewarded(String placement);

  /// Optional warm-up for interstitials (campaign level transitions).
  Future<void> preloadInterstitial();

  /// Shows a rewarded ad for [placement].
  ///
  /// Returns **true only** if the user earned the reward (SDK callback fired).
  Future<bool> showRewarded({required String placement});

  /// Shows an interstitial if one is loaded and cooldown allows (DEBUG: fast cycle;
  /// Release/Profile: 5‑minute pacing for campaign transitions).
  ///
  /// Returns `true` only if an ad was presented (dismissed or failed after [show]).
  /// Cooldown skip, missing inventory, and no-op implementations return `false`.
  Future<bool> showInterstitialIfReady({required String placement});

  /// Bottom anchored adaptive banner slot for daily challenge calendar only.
  /// [NoOpAdService] and tests return zero-height spacer.
  Widget buildDailyChallengeBanner(BuildContext context);

  /// Bottom anchored adaptive banner on the in-game pause overlay.
  /// [NoOpAdService] and tests return zero-height spacer.
  Widget buildGamePauseBanner(BuildContext context);
}
