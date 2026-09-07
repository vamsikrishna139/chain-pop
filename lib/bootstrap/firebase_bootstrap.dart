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

    final isPlaceholder =
        Firebase.app().options.projectId.contains('placeholder');
    if (isPlaceholder && !kDebugMode) {
      throw StateError(
        'Firebase config is placeholder (project_id contains "placeholder"). '
        'Cannot build release without a real google-services.json config.',
      );
    }

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
    if (e is StateError && e.message.contains('placeholder')) {
      rethrow;
    }
    crashReportingReady = false;
    if (kDebugMode) {
      debugPrint('Firebase init skipped (add google-services config): $e\n$st');
    }
  }
}
