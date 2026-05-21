import 'dart:developer' as developer;
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../config/subscription_config.dart';
import 'subscription_service.dart';

class RevenueCatSubscriptionService implements SubscriptionService {
  static const _logName = 'Unbound.Subscription';

  final _isPremiumNotifier = ValueNotifier<bool>(false);

  @override
  ValueListenable<bool> get isPremium => _isPremiumNotifier;

  @override
  Future<void> init() async {
    await Purchases.setLogLevel(
      kDebugMode ? LogLevel.debug : LogLevel.info,
    );

    PurchasesConfiguration? configuration;

    if (Platform.isAndroid) {
      const apiKey = String.fromEnvironment('REVENUECAT_GOOGLE_API_KEY');
      if (apiKey.isNotEmpty) {
        configuration = PurchasesConfiguration(apiKey);
      }
    } else if (Platform.isIOS || Platform.isMacOS) {
      const apiKey = String.fromEnvironment('REVENUECAT_APPLE_API_KEY');
      if (apiKey.isNotEmpty) {
        configuration = PurchasesConfiguration(apiKey);
      }
    }

    if (configuration != null) {
      await Purchases.configure(configuration);
      developer.log('RevenueCat configured successfully.', name: _logName);

      try {
        final customerInfo = await Purchases.getCustomerInfo();
        _updatePremiumState(customerInfo);
        Purchases.addCustomerInfoUpdateListener(_updatePremiumState);
      } catch (e) {
        developer.log('Failed to fetch initial customer info: $e', name: _logName);
      }
    } else {
      developer.log(
        'RevenueCat API key not found in environment. Subscriptions disabled.',
        name: _logName,
      );
    }
  }

  void _updatePremiumState(CustomerInfo customerInfo) {
    final hasPremium = customerInfo
            .entitlements.all[SubscriptionConfig.premiumEntitlementId]?.isActive ==
        true;
    if (_isPremiumNotifier.value != hasPremium) {
      _isPremiumNotifier.value = hasPremium;
      developer.log('Premium state updated: $hasPremium', name: _logName);
    }
  }

  @override
  Future<PurchasePremiumResult> purchasePremium() async {
    try {
      final offerings = await Purchases.getOfferings();
      final current = offerings.current;
      if (current == null || current.availablePackages.isEmpty) {
        developer.log('No offerings available to purchase.', name: _logName);
        return PurchasePremiumResult.unavailable;
      }

      final package =
          current.lifetime ?? current.availablePackages.first;
      final purchaseResult = await Purchases.purchase(
        PurchaseParams.package(package),
      );
      _updatePremiumState(purchaseResult.customerInfo);
      return _isPremiumNotifier.value
          ? PurchasePremiumResult.success
          : PurchasePremiumResult.failed;
    } on PlatformException catch (e) {
      if (PurchasesErrorHelper.getErrorCode(e) ==
          PurchasesErrorCode.purchaseCancelledError) {
        return PurchasePremiumResult.cancelled;
      }
      developer.log('Failed to purchase premium: $e', name: _logName);
      return PurchasePremiumResult.failed;
    } catch (e) {
      developer.log('Failed to purchase premium: $e', name: _logName);
      return PurchasePremiumResult.failed;
    }
  }

  @override
  Future<RestorePurchasesResult> restorePurchases() async {
    try {
      final customerInfo = await Purchases.restorePurchases();
      _updatePremiumState(customerInfo);
      return _isPremiumNotifier.value
          ? RestorePurchasesResult.restored
          : RestorePurchasesResult.noneFound;
    } catch (e) {
      developer.log('Failed to restore purchases: $e', name: _logName);
      return RestorePurchasesResult.failed;
    }
  }
}
