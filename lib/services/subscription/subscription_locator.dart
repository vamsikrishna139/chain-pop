import 'package:flutter/foundation.dart';
import 'subscription_service.dart';

class SubscriptionLocator {
  SubscriptionLocator._();

  static SubscriptionService? _instance;

  static SubscriptionService get instance {
    if (_instance == null) {
      throw StateError(
          'SubscriptionService not installed. Call SubscriptionLocator.install() first.');
    }
    return _instance!;
  }

  static SubscriptionService? get instanceOrNull => _instance;

  static void install(SubscriptionService service) {
    _instance = service;
  }

  @visibleForTesting
  static void uninstall() {
    _instance = null;
  }
}
