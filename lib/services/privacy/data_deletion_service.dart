import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import '../storage/local_progress_reset.dart';
import 'support_identity.dart';

/// What "Delete my data" did, and the IDs as they were *before* the reset —
/// the deletion request email must carry these, not the new ones.
@immutable
class DeletionReceipt {
  const DeletionReceipt({
    required this.previousIds,
    required this.localDataCleared,
    required this.analyticsReset,
    required this.crashReportsCleared,
  });

  final SupportIds previousIds;
  final bool localDataCleared;
  final bool analyticsReset;
  final bool crashReportsCleared;
}

typedef DeletionStep = Future<void> Function();

/// In-app "Delete my data".
///
/// Order matters:
/// 1. capture the current IDs (step 2 replaces the analytics ID);
/// 2. reset Analytics — wipes on-device analytics data and issues a new App
///    Instance ID, so future data is not linked to the past;
/// 3. delete unsent Crashlytics reports;
/// 4. wipe local progress (same helper as "Reset Game Data").
///
/// Deliberately kept: the `settings` Hive box (the analytics on/off choice),
/// the UMP/TCF ad-consent state, and the ad-free entitlement. Deleting data
/// must never quietly re-enable analytics or take back a purchase.
///
/// Server-side copies (Analytics, RevenueCat) can't be deleted from the
/// device; the receipt's IDs go into a deletion request email instead.
class DataDeletionService {
  DataDeletionService({
    SupportIdentity? identity,
    DeletionStep? resetAnalytics,
    DeletionStep? deleteUnsentCrashReports,
    DeletionStep? clearLocalProgress,
  }) : _identity = identity ?? SupportIdentity(),
       _resetAnalytics =
           resetAnalytics ??
           (() => FirebaseAnalytics.instance.resetAnalyticsData()),
       _deleteUnsentCrashReports =
           deleteUnsentCrashReports ??
           (() => FirebaseCrashlytics.instance.deleteUnsentReports()),
       _clearLocalProgress = clearLocalProgress ?? resetLocalProgress;

  final SupportIdentity _identity;
  final DeletionStep _resetAnalytics;
  final DeletionStep _deleteUnsentCrashReports;
  final DeletionStep _clearLocalProgress;

  Future<DeletionReceipt> deleteMyData() async {
    final previous = await _identity.read();
    // Firebase may be missing (tests, misconfigured builds); the local wipe
    // must still happen, so the remote steps never abort the flow.
    final analyticsReset = await _attempt(_resetAnalytics);
    final crashCleared = await _attempt(_deleteUnsentCrashReports);
    await _clearLocalProgress();
    return DeletionReceipt(
      previousIds: previous,
      localDataCleared: true,
      analyticsReset: analyticsReset,
      crashReportsCleared: crashCleared,
    );
  }

  static Future<bool> _attempt(DeletionStep step) async {
    try {
      await step();
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('DataDeletionService: step skipped: $e');
      return false;
    }
  }
}
