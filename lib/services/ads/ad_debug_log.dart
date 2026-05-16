import 'package:flutter/foundation.dart';

/// Debug-only ad pipeline tracing. Filter Android logcat: `ChainPop/Ads`
void adDebug(String message) {
  if (kDebugMode) {
    debugPrint('[ChainPop/Ads] $message');
  }
}
