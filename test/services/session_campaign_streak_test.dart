import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/services/session_campaign_streak.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SessionCampaignStreak', () {
    setUp(SessionCampaignStreak.reset);

    test('interstitialStreakThreshold matches product tuning', () {
      expect(
        SessionCampaignStreak.interstitialStreakThreshold(DifficultyMode.easy),
        4,
      );
      expect(
        SessionCampaignStreak.interstitialStreakThreshold(DifficultyMode.medium),
        3,
      );
      expect(
        SessionCampaignStreak.interstitialStreakThreshold(DifficultyMode.hard),
        2,
      );
    });

    test('onWin increments; reset clears', () {
      expect(SessionCampaignStreak.wins, 0);
      SessionCampaignStreak.onWin();
      SessionCampaignStreak.onWin();
      expect(SessionCampaignStreak.wins, 2);
      SessionCampaignStreak.reset();
      expect(SessionCampaignStreak.wins, 0);
    });
  });
}
