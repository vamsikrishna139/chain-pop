import 'package:chain_pop/services/ads/ad_placements.dart';
import 'package:chain_pop/services/ads/recording_ad_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RecordingAdService', () {
    test('showInterstitialIfReady records placement and honors result flag', () async {
      final ok = RecordingAdService();
      expect(await ok.showInterstitialIfReady(placement: AdPlacements.hint), isTrue);
      expect(ok.betweenLevelsInterstitialShows, 1);
      expect(ok.interstitialPlacements.single, AdPlacements.hint);

      final no = RecordingAdService(interstitialResult: false);
      expect(
        await no.showInterstitialIfReady(placement: AdPlacements.undo),
        isFalse,
      );
      expect(no.betweenLevelsInterstitialShows, 1);
    });

    test('preload paths are observable', () async {
      final ads = RecordingAdService();
      await ads.preloadRewarded(AdPlacements.dailyUnlockPast);
      expect(ads.rewardedPreloadPlacements.single, AdPlacements.dailyUnlockPast);
      await ads.preloadInterstitial();
      expect(ads.preloadInterstitialCalls, 1);
    });

    test('beforeInterstitialRuns hook', () async {
      var ran = false;
      final ads = RecordingAdService(
        beforeInterstitialReturns: () async {
          ran = true;
        },
      );
      await ads.showInterstitialIfReady(placement: AdPlacements.betweenLevelsStreak);
      expect(ran, isTrue);
    });
  });
}
