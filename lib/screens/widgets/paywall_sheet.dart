import 'package:flutter/material.dart';
import '../../services/subscription/subscription_locator.dart';
import '../../services/subscription/subscription_service.dart';

class PaywallSheet extends StatefulWidget {
  const PaywallSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const PaywallSheet(),
    );
  }

  @override
  State<PaywallSheet> createState() => _PaywallSheetState();
}

class _PaywallSheetState extends State<PaywallSheet> {
  bool _isLoading = false;
  String? _price;

  @override
  void initState() {
    super.initState();
    _loadPrice();
  }

  Future<void> _loadPrice() async {
    setState(() => _isLoading = true);
    final price = await SubscriptionLocator.instance.getPremiumPrice();
    if (mounted) {
      setState(() {
        _price = price;
        _isLoading = false;
      });
    }
  }

  Future<void> _purchase() async {
    setState(() => _isLoading = true);
    final result = await SubscriptionLocator.instance.purchasePremium();
    if (mounted) {
      setState(() => _isLoading = false);
      if (result == PurchasePremiumResult.success) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Purchase successful! Ads removed.')),
        );
      } else if (result == PurchasePremiumResult.failed) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Purchase failed. Please try again.')),
        );
      }
    }
  }

  Future<void> _restore() async {
    setState(() => _isLoading = true);
    final result = await SubscriptionLocator.instance.restorePurchases();
    if (mounted) {
      setState(() => _isLoading = false);
      if (result == RestorePurchasesResult.restored) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Purchases restored successfully.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No previous purchases found.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(24),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Unbound Premium',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              'Enjoy a completely ad-free experience.\n'
              'Support the developer and play uninterrupted.',
              style: TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else ...[
              ElevatedButton(
                onPressed: _price != null ? _purchase : null,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: Text(
                  _price != null ? 'Remove Ads for $_price' : 'Not Available',
                  style: const TextStyle(fontSize: 18),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _restore,
                child: const Text('Restore Purchases'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
