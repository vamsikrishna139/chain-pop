import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The privacy policy (§3) promises Analytics is not linked to Google
/// advertising products. These platform flags make that true; a merge that
/// drops them must fail loudly.
void main() {
  test('AndroidManifest keeps Analytics off the advertising ID', () {
    final xml =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    for (final name in [
      'google_analytics_adid_collection_enabled',
      'google_analytics_default_allow_ad_personalization_signals',
    ]) {
      final m = RegExp(
        'android:name="$name"\\s+android:value="([^"]*)"',
      ).firstMatch(xml);
      expect(m, isNotNull, reason: '$name missing from AndroidManifest.xml');
      expect(m!.group(1), 'false', reason: '$name must be false');
    }
  });

  test('iOS Info.plist mirrors the Analytics ad-signal flags', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    for (final key in [
      'GOOGLE_ANALYTICS_IDFV_COLLECTION_ENABLED',
      'GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_PERSONALIZATION_SIGNALS',
    ]) {
      expect(
        RegExp('<key>$key</key>\\s*<false/>').hasMatch(plist),
        isTrue,
        reason: '$key must be <false/> in Info.plist',
      );
    }
  });
}
