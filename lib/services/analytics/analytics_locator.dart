import 'analytics_service.dart';
import 'no_op_analytics_service.dart';

class AnalyticsLocator {
  AnalyticsLocator._();

  static AnalyticsService _instance = NoOpAnalyticsService();

  static AnalyticsService get instance => _instance;

  static void install(AnalyticsService service) {
    _instance = service;
  }
}
