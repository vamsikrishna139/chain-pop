import 'package:flutter/foundation.dart';
import 'subscription_service.dart';

class NoOpSubscriptionService implements SubscriptionService {
  @override
  ValueListenable<bool> get isPremium => ValueNotifier<bool>(false);

  @override
  Future<void> init() async {}

  @override
  Future<PurchasePremiumResult> purchasePremium() async =>
      PurchasePremiumResult.unavailable;

  @override
  Future<RestorePurchasesResult> restorePurchases() async =>
      RestorePurchasesResult.noneFound;
}
