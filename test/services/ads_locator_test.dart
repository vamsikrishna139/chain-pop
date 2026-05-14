import 'package:chain_pop/services/ads/ads_locator.dart';
import 'package:chain_pop/services/ads/recording_ad_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AdsLocator.install replaces default instance', () {
    final original = AdsLocator.instance;
    final recording = RecordingAdService();
    try {
      AdsLocator.install(recording);
      expect(identical(AdsLocator.instance, recording), isTrue);
    } finally {
      AdsLocator.install(original);
    }
  });
}
