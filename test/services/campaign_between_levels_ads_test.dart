import 'dart:io';

import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/services/ads/ad_placements.dart';
import 'package:chain_pop/services/ads/campaign_between_levels_ads.dart';
import 'package:chain_pop/services/ads/campaign_interstitial_frustration_gate.dart';
import 'package:chain_pop/services/ads/recording_ad_service.dart';
import 'package:chain_pop/services/session_campaign_streak.dart';
import 'package:chain_pop/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CampaignBetweenLevelsAds', () {
    group('ignoreEngagementGates (pure streak / placement smoke)', () {
      setUp(() {
        SessionCampaignStreak.reset();
        CampaignInterstitialFrustrationGate.resetForTests();
      });

      test('does not show below easy threshold (4 wins)', () async {
        SessionCampaignStreak.onWin();
        SessionCampaignStreak.onWin();
        SessionCampaignStreak.onWin();
        final ads = RecordingAdService();
        final shown = await CampaignBetweenLevelsAds.maybePresentForCampaignTransition(
          ads: ads,
          difficulty: DifficultyMode.easy,
          isTutorial: false,
          isDailyChallenge: false,
          ignoreEngagementGates: true,
        );
        expect(shown, isFalse);
        expect(ads.betweenLevelsInterstitialShows, 0);
        expect(SessionCampaignStreak.wins, 3);
      });

      test('shows at easy threshold when inventory presents', () async {
        SessionCampaignStreak.onWin();
        SessionCampaignStreak.onWin();
        SessionCampaignStreak.onWin();
        SessionCampaignStreak.onWin();
        final ads = RecordingAdService();
        final shown = await CampaignBetweenLevelsAds.maybePresentForCampaignTransition(
          ads: ads,
          difficulty: DifficultyMode.easy,
          isTutorial: false,
          isDailyChallenge: false,
          ignoreEngagementGates: true,
        );
        expect(shown, isTrue);
        expect(ads.betweenLevelsInterstitialShows, 1);
        expect(
          ads.interstitialPlacements.single,
          AdPlacements.betweenLevelsStreak,
        );
        expect(SessionCampaignStreak.wins, 0);
      });

      test('does not reset streak when placement returns false', () async {
        SessionCampaignStreak.onWin();
        SessionCampaignStreak.onWin();
        SessionCampaignStreak.onWin();
        SessionCampaignStreak.onWin();
        final ads = RecordingAdService(interstitialResult: false);
        final shown = await CampaignBetweenLevelsAds.maybePresentForCampaignTransition(
          ads: ads,
          difficulty: DifficultyMode.easy,
          isTutorial: false,
          isDailyChallenge: false,
          ignoreEngagementGates: true,
        );
        expect(shown, isFalse);
        expect(ads.betweenLevelsInterstitialShows, 1);
        expect(SessionCampaignStreak.wins, 4);
      });

      test('skips tutorial and daily runs', () async {
        SessionCampaignStreak.onWin();
        SessionCampaignStreak.onWin();
        SessionCampaignStreak.onWin();
        SessionCampaignStreak.onWin();
        final ads = RecordingAdService();
        await CampaignBetweenLevelsAds.maybePresentForCampaignTransition(
          ads: ads,
          difficulty: DifficultyMode.easy,
          isTutorial: true,
          isDailyChallenge: false,
          ignoreEngagementGates: true,
        );
        expect(ads.betweenLevelsInterstitialShows, 0);

        await CampaignBetweenLevelsAds.maybePresentForCampaignTransition(
          ads: ads,
          difficulty: DifficultyMode.easy,
          isTutorial: false,
          isDailyChallenge: true,
          ignoreEngagementGates: true,
        );
        expect(ads.betweenLevelsInterstitialShows, 0);
      });

      test('medium uses threshold 3', () async {
        SessionCampaignStreak.onWin();
        SessionCampaignStreak.onWin();
        SessionCampaignStreak.onWin();
        final ads = RecordingAdService();
        await CampaignBetweenLevelsAds.maybePresentForCampaignTransition(
          ads: ads,
          difficulty: DifficultyMode.medium,
          isTutorial: false,
          isDailyChallenge: false,
          ignoreEngagementGates: true,
        );
        expect(ads.betweenLevelsInterstitialShows, 1);
      });

      test('hard uses threshold 2', () async {
        SessionCampaignStreak.onWin();
        SessionCampaignStreak.onWin();
        final ads = RecordingAdService();
        await CampaignBetweenLevelsAds.maybePresentForCampaignTransition(
          ads: ads,
          difficulty: DifficultyMode.hard,
          isTutorial: false,
          isDailyChallenge: false,
          ignoreEngagementGates: true,
        );
        expect(ads.betweenLevelsInterstitialShows, 1);
      });
    });

    group('engagement gates live', () {
      setUpAll(() async {
        final tempDir = await Directory.systemTemp.createTemp(
          'chain_pop_campaign_between_ads_',
        );
        Hive.init(tempDir.path);
        await StorageService.init();
      });

      setUp(() async {
        await StorageService.clearProgress();
        SessionCampaignStreak.reset();
        CampaignInterstitialFrustrationGate.resetForTests();
      });

      test('lifetime onboarding gate suppresses streak-qualified transitions', () async {
        SessionCampaignStreak.onWin();
        SessionCampaignStreak.onWin();
        SessionCampaignStreak.onWin();
        SessionCampaignStreak.onWin();
        final ads = RecordingAdService();

        expect(StorageService.campaignInterstitialLifetimeGateSatisfied, isFalse);

        final shown = await CampaignBetweenLevelsAds.maybePresentForCampaignTransition(
          ads: ads,
          difficulty: DifficultyMode.easy,
          isTutorial: false,
          isDailyChallenge: false,
        );
        expect(shown, isFalse);
        expect(ads.betweenLevelsInterstitialShows, 0);
        expect(SessionCampaignStreak.wins, 4);

        await StorageService.seedLifetimeEngagementGateForTests();
        final shown2 =
            await CampaignBetweenLevelsAds.maybePresentForCampaignTransition(
          ads: ads,
          difficulty: DifficultyMode.easy,
          isTutorial: false,
          isDailyChallenge: false,
        );
        expect(shown2, isTrue);
        expect(ads.betweenLevelsInterstitialShows, 1);
      });

      test('recent fail streak suppresses when lifetime gate passes', () async {
        CampaignInterstitialFrustrationGate.noteFailedRunEnded();
        CampaignInterstitialFrustrationGate.noteFailedRunEnded();
        SessionCampaignStreak.onWin();
        SessionCampaignStreak.onWin();
        SessionCampaignStreak.onWin();
        SessionCampaignStreak.onWin();
        await StorageService.seedLifetimeEngagementGateForTests();
        final ads = RecordingAdService();
        final shown = await CampaignBetweenLevelsAds.maybePresentForCampaignTransition(
          ads: ads,
          difficulty: DifficultyMode.easy,
          isTutorial: false,
          isDailyChallenge: false,
        );
        expect(shown, isFalse);
        expect(ads.betweenLevelsInterstitialShows, 0);
      });
    });
  });
}
