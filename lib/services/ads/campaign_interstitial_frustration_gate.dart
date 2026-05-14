import 'package:flutter/foundation.dart';

/// In-memory suppression for between-level campaign interstitials when the player
/// has recently lost runs back-to-back (sliding window).
abstract final class CampaignInterstitialFrustrationGate {
  CampaignInterstitialFrustrationGate._();

  static const Duration _window = Duration(minutes: 3);

  static final List<DateTime> _recentFails = [];

  @visibleForTesting
  static void resetForTests() => _recentFails.clear();

  static void noteFailedRunEnded() {
    final now = DateTime.now();
    _recentFails.add(now);
    _purge(now);
  }

  /// A campaign win resets frustration tracking so normal pacing resumes.
  static void noteCampaignWin() => _recentFails.clear();

  static bool shouldSuppressInterstitial() {
    _purge(DateTime.now());
    return _recentFails.length >= 2;
  }

  static void _purge(DateTime now) {
    final cutoff = now.subtract(_window);
    _recentFails.removeWhere((t) => t.isBefore(cutoff));
  }
}
