import 'package:flutter/foundation.dart';
import 'package:chain_pop/services/subscription/subscription_service.dart';

class TestSubscriptionService implements SubscriptionService {
  final ValueNotifier<bool> _isPremium = ValueNotifier<bool>(false);

  @override
  ValueListenable<bool> get isPremium => _isPremium;

  void setPremium(bool value) {
    _isPremium.value = value;
  }

  @override
  Future<void> init() async {}

  @override
  Future<PurchasePremiumResult> purchasePremium() async =>
      PurchasePremiumResult.success;

  @override
  Future<RestorePurchasesResult> restorePurchases() async =>
      RestorePurchasesResult.noneFound;
}
