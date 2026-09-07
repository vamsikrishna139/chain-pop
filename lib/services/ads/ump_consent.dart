import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_debug_log.dart';

/// Requests GDPR / UMP consent before ads load (native User Messaging Platform).
///
/// Depends on `google_mobile_ads` UMP bindings; Android integrates WebView via
/// `webview_flutter` as documented for Flutter + AdMob consent flows.
Future<bool> requestAdsConsentIfApplicable() async {
  if (!(defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS)) {
    adDebug('UMP: skip (not Android/iOS)');
    return true;
  }

  adDebug('UMP: requestConsentInfoUpdate starting');

  // Two separate stages, with separate bounds:
  //  1. `infoUpdate` — a pure network round trip. Bounded tightly (10s) so a
  //     dead network never blocks ad init for the session.
  //  2. `formDone` — may include the user reading and dismissing the GDPR
  //     form. Bounded only by a generous safety net so a slow reader is never
  //     cut off (the old single-completer 10s guillotine killed ads for the
  //     whole session for anyone who took their time on the form).
  final infoUpdate = Completer<bool>();
  final formDone = Completer<void>();

  final params = ConsentRequestParameters(
    consentDebugSettings: kDebugMode
        ? ConsentDebugSettings(
            debugGeography: DebugGeography.debugGeographyEea,
            testIdentifiers: [
              '698E8E4CEB6E2D57599CAB6E8F9459A9',
              // Pixel 8a (akita) — without this the EEA debug geography above
              // is inert on that device and the consent form never shows.
              'FCFF773E74258AAE1B16B64A296FD9ED',
            ],
          )
        : null,
  );

  ConsentInformation.instance.requestConsentInfoUpdate(
    params,
    () {
      adDebug('UMP: consent info updated, may show form');
      if (!infoUpdate.isCompleted) infoUpdate.complete(true);
      unawaited(_presentConsentThen(formDone));
    },
    (FormError error) {
      adDebug('UMP: consent info update failed: ${error.message}');
      if (kDebugMode) {
        debugPrint('UMP consent info update failed: ${error.message}');
      }
      if (!infoUpdate.isCompleted) infoUpdate.complete(false);
      if (!formDone.isCompleted) formDone.complete();
    },
  );

  // Stage 1: network only.
  bool infoOk;
  try {
    infoOk = await infoUpdate.future.timeout(const Duration(seconds: 10));
  } on TimeoutException {
    adDebug(
        'UMP: consent info update timed out — not proceeding to MobileAds.initialize.');
    if (kDebugMode) {
      debugPrint(
          'UMP: consent info update timed out — not proceeding to MobileAds.initialize.');
    }
    return false;
  }

  if (!infoOk) {
    adDebug('UMP: consent not established — skipping MobileAds.initialize.');
    return false;
  }

  // Stage 2: form load + human interaction. No short guillotine here; the
  // long bound only exists so a wedged form can never hang startup forever.
  try {
    await formDone.future.timeout(const Duration(minutes: 5));
    adDebug('UMP: flow finished (proceed to MobileAds.initialize)');
  } on TimeoutException {
    adDebug('UMP: consent form never resolved (5m) — proceeding anyway.');
    if (kDebugMode) {
      debugPrint('UMP: consent form never resolved (5m) — proceeding anyway.');
    }
  }
  // Consent info was established successfully, so ad init is allowed even if
  // the form stage misbehaved: the SDK applies whatever consent it holds.
  return true;
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

/// Checks if the privacy options form is required to be shown (e.g., in GDPR regions).
Future<bool> isPrivacyOptionsRequired() async {
  final status =
      await ConsentInformation.instance.getPrivacyOptionsRequirementStatus();
  return status == PrivacyOptionsRequirementStatus.required;
}

/// Presents the privacy options form so the user can change their consent later.
Future<void> showPrivacyOptionsForm() async {
  final done = Completer<void>();
  ConsentForm.showPrivacyOptionsForm((FormError? formError) {
    if (formError != null) {
      adDebug('UMP: privacy options form error: ${formError.message}');
      if (kDebugMode) {
        debugPrint('UMP privacy options form error: ${formError.message}');
      }
    } else {
      // The MobileAds SDK automatically uses the updated consent status
      // for the next ad request. No hard restart is strictly required.
      adDebug(
          'UMP: privacy options form closed. Next ad request will use updated consent.');
    }
    if (!done.isCompleted) done.complete();
  });
  return done.future;
}
