import 'package:chain_pop/services/analytics/analytics_consent.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

void main() {
  group('AnalyticsConsentDecision.decide', () {
    test('GDPR region, all purposes consented → everything granted', () {
      final d = AnalyticsConsentDecision.decide(
        gdprApplies: 1,
        purposeConsents: '11111111111',
      );
      expect(d.analyticsStorage, isTrue);
      expect(d.adStorage, isTrue);
      expect(d.adUserData, isTrue);
      expect(d.adPersonalization, isTrue);
    });

    test('GDPR region, "Do not consent" → everything denied', () {
      final d = AnalyticsConsentDecision.decide(
        gdprApplies: 1,
        purposeConsents: '00000000000',
      );
      expect(d.analyticsStorage, isFalse);
      expect(d.adStorage, isFalse);
      expect(d.adUserData, isFalse);
      expect(d.adPersonalization, isFalse);
    });

    test('GDPR region, storage only → analytics yes, personalization no', () {
      final d = AnalyticsConsentDecision.decide(
        gdprApplies: 1,
        purposeConsents: '1000000',
      );
      expect(d.analyticsStorage, isTrue);
      expect(d.adUserData, isFalse);
      expect(d.adPersonalization, isFalse);
    });

    test('GDPR region with missing purpose string denies', () {
      final d = AnalyticsConsentDecision.decide(gdprApplies: 1);
      expect(d.analyticsStorage, isFalse);
    });

    test('outside GDPR → granted', () {
      final d = AnalyticsConsentDecision.decide(gdprApplies: 0);
      expect(d.analyticsStorage, isTrue);
    });

    test('no TCF data falls back to UMP status', () {
      expect(
        AnalyticsConsentDecision.decide(umpStatus: ConsentStatus.notRequired)
            .analyticsStorage,
        isTrue,
      );
      expect(
        AnalyticsConsentDecision.decide(umpStatus: ConsentStatus.required)
            .analyticsStorage,
        isFalse,
      );
      expect(
        AnalyticsConsentDecision.decide(umpStatus: ConsentStatus.unknown)
            .analyticsStorage,
        isFalse,
      );
      expect(AnalyticsConsentDecision.decide().analyticsStorage, isFalse);
    });
  });
}
