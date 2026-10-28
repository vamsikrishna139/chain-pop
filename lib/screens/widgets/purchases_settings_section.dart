import 'package:flutter/material.dart';

import '../../services/subscription/subscription_locator.dart';
import '../../services/subscription/subscription_service.dart';
import '../../theme/app_colors.dart';
import 'paywall_sheet.dart';

/// Remove-ads purchase and restore controls for settings sheets.
class PurchasesSettingsSection extends StatelessWidget {
  final Color accent;

  const PurchasesSettingsSection({super.key, required this.accent});



  Future<void> _restore(BuildContext context) async {
    final result = await SubscriptionLocator.instance.restorePurchases();
    if (!context.mounted) return;
    switch (result) {
      case RestorePurchasesResult.restored:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Purchases restored successfully!')),
        );
      case RestorePurchasesResult.noneFound:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No previous purchases found.')),
        );
      case RestorePurchasesResult.failed:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not restore purchases. Try again.'),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SubscriptionLocator.instance.isPremium,
      builder: (context, isPremium, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Purchases',
              style: TextStyle(
                color: accent,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 8),
            if (isPremium)
              const Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'Forever Ad-Free Unlocked',
                    style: TextStyle(
                      color: AppColors.starGold,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              )
            else
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => PaywallSheet.show(context),
                  icon: const Icon(
                    Icons.star_rounded,
                    color: AppColors.starGold,
                    size: 18,
                  ),
                  label: FutureBuilder<String?>(
                    future: SubscriptionLocator.instance.getPremiumPrice(),
                    builder: (context, snapshot) {
                      final price = snapshot.data;
                      final text = price != null ? 'Remove Ads ($price)' : 'Remove Ads';
                      return Text(
                        text,
                        style: const TextStyle(
                          color: AppColors.starGold,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    },
                  ),
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _restore(context),
                icon: const Icon(
                  Icons.restore_outlined,
                  color: Colors.white70,
                  size: 18,
                ),
                label: const Text(
                  'Restore purchases',
                  style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const Divider(color: Colors.white10, height: 32),
          ],
        );
      },
    );
  }
}
