import 'package:flutter/foundation.dart';

enum PurchasePremiumResult { success, cancelled, failed, unavailable }

enum RestorePurchasesResult { restored, noneFound, failed }

abstract class SubscriptionService {
  /// Whether the user has the premium entitlement (no ads).
  ValueListenable<bool> get isPremium;

  /// Initializes the subscription SDK (e.g., RevenueCat).
  Future<void> init();

  /// Prompts the user to purchase the premium entitlement.
  Future<PurchasePremiumResult> purchasePremium();

  /// Restores previous purchases from the store account.
  Future<RestorePurchasesResult> restorePurchases();

  /// Refreshes the premium entitlement state.
  Future<void> refresh();

  /// Gets the localized price string of the premium entitlement.
  Future<String?> getPremiumPrice();
}
