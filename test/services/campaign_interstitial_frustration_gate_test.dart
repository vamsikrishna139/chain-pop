import 'package:chain_pop/services/ads/campaign_interstitial_frustration_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CampaignInterstitialFrustrationGate', () {
    setUp(CampaignInterstitialFrustrationGate.resetForTests);

    test('no suppression until two failures recorded', () {
      expect(CampaignInterstitialFrustrationGate.shouldSuppressInterstitial(), isFalse);
      CampaignInterstitialFrustrationGate.noteFailedRunEnded();
      expect(CampaignInterstitialFrustrationGate.shouldSuppressInterstitial(), isFalse);
      CampaignInterstitialFrustrationGate.noteFailedRunEnded();
      expect(CampaignInterstitialFrustrationGate.shouldSuppressInterstitial(), isTrue);
    });

    test('noteCampaignWin clears frustration tracking', () {
      CampaignInterstitialFrustrationGate.noteFailedRunEnded();
      CampaignInterstitialFrustrationGate.noteFailedRunEnded();
      expect(CampaignInterstitialFrustrationGate.shouldSuppressInterstitial(), isTrue);
      CampaignInterstitialFrustrationGate.noteCampaignWin();
      expect(CampaignInterstitialFrustrationGate.shouldSuppressInterstitial(), isFalse);
    });

    test('resetForTests clears state', () {
      CampaignInterstitialFrustrationGate.noteFailedRunEnded();
      CampaignInterstitialFrustrationGate.noteFailedRunEnded();
      CampaignInterstitialFrustrationGate.resetForTests();
      expect(CampaignInterstitialFrustrationGate.shouldSuppressInterstitial(), isFalse);
    });
  });
}
