import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import '../services/crash_reporting.dart';

/// Initializes Firebase when native config exists (`google-services.json` /
/// `GoogleService-Info.plist`). Safe to call on CI / tests — failures are swallowed.
///
/// See README for replacing placeholder configs.
Future<void> initFirebaseChainPop() async {
  try {
    if (Firebase.apps.isNotEmpty) {
      crashReportingReady = true;
      return;
    }
    await Firebase.initializeApp();
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
      !kDebugMode ||
          const bool.fromEnvironment(
            'CHAINPOP_FORCE_CRASHLYTICS_IN_DEBUG',
            defaultValue: false,
          ),
    );
    crashReportingReady = true;
    try {
      await FirebaseAnalytics.instance.logAppOpen();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Firebase Analytics logAppOpen skipped: $e\n$st');
      }
    }
  } catch (e, st) {
    crashReportingReady = false;
    if (kDebugMode) {
      debugPrint('Firebase init skipped (add google-services config): $e\n$st');
    }
  }
}
