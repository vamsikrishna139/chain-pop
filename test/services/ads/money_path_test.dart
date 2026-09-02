import 'package:flutter_test/flutter_test.dart';
import 'package:chain_pop/services/ads/ad_placements.dart';
import 'package:chain_pop/services/ads/premium_ad_service_decorator.dart';
import 'package:chain_pop/services/subscription/subscription_locator.dart';
import '../subscription/test_subscription_service.dart';
import 'recording_ad_service.dart';

void main() {
  group('Money Path & Premium Bypass', () {
    late RecordingAdService innerAds;
    late PremiumAdServiceDecorator premiumAds;
    late TestSubscriptionService mockSubs;

    setUp(() {
      innerAds = RecordingAdService(rewardedResult: true);
      premiumAds = PremiumAdServiceDecorator(innerAds);
      mockSubs = TestSubscriptionService();
      SubscriptionLocator.install(mockSubs);
    });

    test('premium suppresses interstitial ads', () async {
      mockSubs.setPremium(true);
      final result = await premiumAds.showInterstitialIfReady(
          placement: AdPlacements.betweenLevelsStreak);
      expect(result, isFalse);
      expect(innerAds.betweenLevelsInterstitialShows, 0);
    });

    test('premium does not suppress rewarded ads but allows them', () async {
      mockSubs.setPremium(true);
      final result =
          await premiumAds.showRewarded(placement: AdPlacements.undo);
      expect(result, isTrue);
    });

    test('rewarded success grants correctly', () async {
      mockSubs.setPremium(false);
      innerAds = RecordingAdService(rewardedResult: true);
      premiumAds = PremiumAdServiceDecorator(innerAds);

      final result =
          await premiumAds.showRewarded(placement: AdPlacements.undo);
      expect(result, isTrue);
    });

    test('rewarded failure grants nothing', () async {
      mockSubs.setPremium(false);
      innerAds = RecordingAdService(rewardedResult: false);
      premiumAds = PremiumAdServiceDecorator(innerAds);

      final result =
          await premiumAds.showRewarded(placement: AdPlacements.undo);
      expect(result, isFalse);
    });
  });
}
