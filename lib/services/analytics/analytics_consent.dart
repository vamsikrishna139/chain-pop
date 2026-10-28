import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Consent signals derived from the UMP / IAB TCF state on the device.
@immutable
class AnalyticsConsentDecision {
  final bool analyticsStorage;
  final bool adStorage;
  final bool adUserData;
  final bool adPersonalization;

  const AnalyticsConsentDecision({
    required this.analyticsStorage,
    required this.adStorage,
    required this.adUserData,
    required this.adPersonalization,
  });

  static const granted = AnalyticsConsentDecision(
    analyticsStorage: true,
    adStorage: true,
    adUserData: true,
    adPersonalization: true,
  );

  static const denied = AnalyticsConsentDecision(
    analyticsStorage: false,
    adStorage: false,
    adUserData: false,
    adPersonalization: false,
  );

  /// Maps the TCF keys the UMP SDK writes into Google consent-mode signals.
  ///
  /// - GDPR applies → TCF purposes decide: storage needs Purpose 1, ad user
  ///   data Purposes 1+7, ad personalization Purposes 3+4 (Google's published
  ///   TCF → consent-mode mapping). Analytics storage follows Purpose 1, the
  ///   device-storage consent ePrivacy requires for the app instance ID.
  /// - GDPR does not apply → granted.
  /// - No TCF data → fall back to the UMP status: "not required" / "obtained"
  ///   grant; "required" / "unknown" (e.g. first launch offline) deny until a
  ///   later session resolves it.
  static AnalyticsConsentDecision decide({
    int? gdprApplies,
    String? purposeConsents,
    ConsentStatus? umpStatus,
  }) {
    if (gdprApplies == 1) {
      final p = purposeConsents ?? '';
      bool purpose(int n) => p.length >= n && p[n - 1] == '1';
      return AnalyticsConsentDecision(
        analyticsStorage: purpose(1),
        adStorage: purpose(1),
        adUserData: purpose(1) && purpose(7),
        adPersonalization: purpose(3) && purpose(4),
      );
    }
    if (gdprApplies == 0) return granted;
    if (umpStatus == ConsentStatus.notRequired ||
        umpStatus == ConsentStatus.obtained) {
      return granted;
    }
    return denied;
  }
}

/// Gates Firebase Analytics on both the GDPR consent (via UMP) and the
/// player's own "Share usage analytics" switch.
///
/// Collection starts disabled from the manifest
/// (`firebase_analytics_collection_enabled=false`) and is only switched on by
/// [apply], so nothing is logged before the consent flow has run.
class AnalyticsConsent {
  AnalyticsConsent._();

  static const _channel = MethodChannel('com.adbkv.chainpop/tcf');
  static const _boxName = 'settings';
  static const _enabledKey = 'analytics_enabled';

  static bool _userEnabled = true;
  static bool _appOpenLogged = false;
  static AnalyticsConsentDecision _decision = AnalyticsConsentDecision.denied;

  /// The player's own preference (defaults on).
  static bool get userEnabled => _userEnabled;

  static bool get collectionEnabled =>
      _userEnabled && _decision.analyticsStorage;

  static Future<void> load() async {
    final box = await Hive.openBox(_boxName);
    _userEnabled = box.get(_enabledKey, defaultValue: true) as bool;
  }

  static Future<void> setUserEnabled(bool enabled) async {
    _userEnabled = enabled;
    final box = await Hive.openBox(_boxName);
    await box.put(_enabledKey, enabled);
    await _push();
  }

  /// Re-reads the consent state and pushes it to Firebase. Call after the
  /// UMP flow and after the privacy options form closes.
  static Future<void> apply() async {
    if (kIsWeb) return;
    int? gdprApplies;
    String? purposes;
    // iOS has no TCF bridge yet and falls back to the UMP status.
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        final tcf = await _channel.invokeMapMethod<String, Object?>('read');
        gdprApplies = tcf?['gdprApplies'] as int?;
        purposes = tcf?['purposeConsents'] as String?;
      } catch (e) {
        if (kDebugMode) debugPrint('AnalyticsConsent: TCF read failed: $e');
      }
    }
    ConsentStatus? status;
    try {
      status = await ConsentInformation.instance.getConsentStatus();
    } catch (_) {}
    _decision = AnalyticsConsentDecision.decide(
      gdprApplies: gdprApplies,
      purposeConsents: purposes,
      umpStatus: status,
    );
    if (kDebugMode) {
      debugPrint('AnalyticsConsent: gdpr=$gdprApplies purposes=$purposes '
          'ump=$status → analytics=${_decision.analyticsStorage} '
          'user=$_userEnabled');
    }
    await _push();
  }

  static Future<void> _push() async {
    try {
      final analytics = FirebaseAnalytics.instance;
      await analytics.setConsent(
        analyticsStorageConsentGranted: _decision.analyticsStorage,
        adStorageConsentGranted: _decision.adStorage,
        adUserDataConsentGranted: _decision.adUserData,
        adPersonalizationSignalsConsentGranted: _decision.adPersonalization,
      );
      await analytics.setAnalyticsCollectionEnabled(collectionEnabled);
      if (collectionEnabled && !_appOpenLogged) {
        _appOpenLogged = true;
        await analytics.logAppOpen();
      }
    } catch (e) {
      // Firebase missing (tests / CI without config) — nothing to gate.
      if (kDebugMode) debugPrint('AnalyticsConsent: Firebase push skipped: $e');
    }
  }
}
