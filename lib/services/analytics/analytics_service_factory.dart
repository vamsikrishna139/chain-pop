import 'package:flutter/foundation.dart';

import 'analytics_service.dart';
import 'firebase_analytics_service.dart';
import 'no_op_analytics_service.dart';

AnalyticsService createDefaultAnalyticsService() {
  if (kIsWeb ||
      (defaultTargetPlatform != TargetPlatform.android &&
          defaultTargetPlatform != TargetPlatform.iOS)) {
    return NoOpAnalyticsService();
  }

  if (const bool.fromEnvironment('MOCK_ANALYTICS', defaultValue: false)) {
    return NoOpAnalyticsService();
  }

  return FirebaseAnalyticsService();
}
