import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_debug_log.dart';

/// Requests GDPR / UMP consent before ads load (native User Messaging Platform).
///
/// Depends on `google_mobile_ads` UMP bindings; Android integrates WebView via
/// `webview_flutter` as documented for Flutter + AdMob consent flows.
Future<void> requestAdsConsentIfApplicable() async {
  if (!(defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS)) {
    adDebug('UMP: skip (not Android/iOS)');
    return;
  }

  adDebug('UMP: requestConsentInfoUpdate starting');
  final done = Completer<void>();
  ConsentInformation.instance.requestConsentInfoUpdate(
    ConsentRequestParameters(),
    () {
      adDebug('UMP: consent info updated, may show form');
      unawaited(_presentConsentThen(done));
    },
    (FormError error) {
      adDebug('UMP: consent info update failed: ${error.message}');
      if (kDebugMode) {
        debugPrint('UMP consent info update failed: ${error.message}');
      }
      if (!done.isCompleted) done.complete();
    },
  );
  await done.future;
  adDebug('UMP: flow finished (proceed to MobileAds.initialize)');
}

Future<void> _presentConsentThen(Completer<void> done) async {
  try {
    await ConsentForm.loadAndShowConsentFormIfRequired((_) {});
    adDebug('UMP: loadAndShowConsentFormIfRequired done');
  } catch (e, st) {
    adDebug('UMP: consent form error: $e');
    if (kDebugMode) {
      debugPrint('UMP consent form error: $e\n$st');
    }
  } finally {
    if (!done.isCompleted) done.complete();
  }
}
