import 'package:chain_pop/services/ads/ad_placements.dart';
import 'package:chain_pop/services/ads/no_op_ad_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NoOpAdService', () {
    test('rewarded and interstitial never present', () async {
      final ads = NoOpAdService();
      expect(ads.isRewardedReady(AdPlacements.hint), isFalse);
      expect(await ads.showRewarded(placement: AdPlacements.hint), isFalse);
      expect(
        await ads.showInterstitialIfReady(placement: AdPlacements.betweenLevelsStreak),
        isFalse,
      );
    });

    test('preloadRewarded notifies inventory listener', () async {
      final ads = NoOpAdService();
      var notifications = 0;
      ads.setInventoryListener(() => notifications++);
      await ads.preloadRewarded(AdPlacements.undo);
      expect(notifications, 1);
    });

    test('clearInventoryListenerIfSame only clears matching listener', () async {
      final ads = NoOpAdService();
      var n = 0;
      void l1() => n++;
      void l2() => n++;
      ads.setInventoryListener(l1);
      ads.clearInventoryListenerIfSame(l2);
      await ads.preloadRewarded(AdPlacements.undo);
      expect(n, 1);
      ads.clearInventoryListenerIfSame(l1);
      await ads.preloadRewarded(AdPlacements.undo);
      expect(n, 1);
    });
  });
}
