import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Whether [FirebaseCrashlytics] was wired successfully during bootstrap.
bool crashReportingReady = false;

void recordFlutterFatal(FlutterErrorDetails details) {
  if (!crashReportingReady) return;
  FirebaseCrashlytics.instance.recordFlutterFatalError(details);
}

void recordNonFatal(Object error, StackTrace stack) {
  if (!crashReportingReady) return;
  FirebaseCrashlytics.instance.recordError(error, stack, fatal: false);
}

bool handleUncaughtZoneError(Object error, StackTrace stack) {
  if (!crashReportingReady) return false;
  FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
  return true;
}
