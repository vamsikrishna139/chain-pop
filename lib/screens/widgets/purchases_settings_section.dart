import 'package:flutter/material.dart';

import '../../services/subscription/subscription_locator.dart';
import '../../services/subscription/subscription_service.dart';
import '../../theme/app_colors.dart';
import 'paywall_sheet.dart';

/// Remove-ads purchase and restore controls for settings sheets.
///
/// The restore result is shown inline, under the button. This section lives
/// in a modal sheet, and a SnackBar would render on the page behind it,
/// hidden until the sheet closes.
class PurchasesSettingsSection extends StatefulWidget {
  final Color accent;

  const PurchasesSettingsSection({super.key, required this.accent});

  @override
  State<PurchasesSettingsSection> createState() =>
      _PurchasesSettingsSectionState();
}

class _PurchasesSettingsSectionState extends State<PurchasesSettingsSection> {
  bool _restoring = false;
  String? _restoreMessage;

  Future<void> _restore() async {
    if (_restoring) return;
    setState(() {
      _restoring = true;
      _restoreMessage = null;
    });
    final result = await SubscriptionLocator.instance.restorePurchases();
    if (!mounted) return;
    setState(() {
      _restoring = false;
      _restoreMessage = restoreResultMessage(result);
    });
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
                color: widget.accent,
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
                      final text =
                          price != null ? 'Remove Ads ($price)' : 'Remove Ads';
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
                onPressed: _restoring ? null : _restore,
                icon: _restoring
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white70,
                        ),
                      )
                    : const Icon(
                        Icons.restore_outlined,
                        color: Colors.white70,
                        size: 18,
                      ),
                label: Text(
                  _restoring ? 'Restoring…' : 'Restore purchases',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            if (_restoreMessage != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Text(
                  _restoreMessage!,
                  key: const Key('restore-result'),
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            const Divider(color: Colors.white10, height: 32),
          ],
        );
      },
    );
  }
}

/// What to tell the player after a restore attempt.
String restoreResultMessage(RestorePurchasesResult result) {
  switch (result) {
    case RestorePurchasesResult.restored:
      return 'Purchases restored. Ads are off.';
    case RestorePurchasesResult.noneFound:
      return 'No previous purchases found for this Google account.';
    case RestorePurchasesResult.failed:
      return "Couldn't reach Google Play. Check your connection and try again.";
  }
}
