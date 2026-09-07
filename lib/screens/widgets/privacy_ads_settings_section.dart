import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/chain_pop_legal.dart';
import '../../services/ads/ump_consent.dart';
import '../../services/notification_service.dart';
import '../game/widgets/privacy_rights_sheet.dart';

/// Privacy policy, rights, and UMP ad-choice controls for settings sheets.
class PrivacyAdsSettingsSection extends StatefulWidget {
  final Color accent;

  /// When true, closes the parent bottom sheet before opening the UMP form.
  final bool popSheetBeforeAdChoices;

  const PrivacyAdsSettingsSection({
    super.key,
    required this.accent,
    this.popSheetBeforeAdChoices = true,
  });

  @override
  State<PrivacyAdsSettingsSection> createState() =>
      _PrivacyAdsSettingsSectionState();
}

class _PrivacyAdsSettingsSectionState extends State<PrivacyAdsSettingsSection> {
  bool _privacyOptionsRequired = false;

  @override
  void initState() {
    super.initState();
    _loadPrivacyOptionsRequired();
  }

  Future<void> _loadPrivacyOptionsRequired() async {
    final required = await isPrivacyOptionsRequired();
    if (!mounted) return;
    setState(() => _privacyOptionsRequired = required);
  }

  Future<void> _openPrivacyPolicy() async {
    final uri = Uri.parse(ChainPopLegal.privacyPolicyUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _openAdChoices() {
    if (widget.popSheetBeforeAdChoices) {
      Navigator.of(context).pop();
    }
    showPrivacyOptionsForm();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Privacy & Ads',
          style: TextStyle(
            color: widget.accent,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 8),
        if (_privacyOptionsRequired)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _openAdChoices,
              icon: const Icon(
                Icons.tune,
                color: Colors.white70,
                size: 18,
              ),
              label: const Text(
                'Manage ad choices',
                style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              showPrivacyRightsSheet(
                context: context,
                accent: widget.accent,
                showAdChoicesButton: _privacyOptionsRequired,
              );
            },
            icon: const Icon(
              Icons.shield_outlined,
              color: Colors.white70,
              size: 18,
            ),
            label: const Text(
              'Privacy rights',
              style: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _openPrivacyPolicy,
            icon: const Icon(
              Icons.article_outlined,
              color: Colors.white70,
              size: 18,
            ),
            label: const Text(
              'Privacy policy',
              style: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        SwitchListTile(
          title: const Text(
            'Daily Reminders',
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
          value: NotificationService.instance.notificationsEnabled,
          activeThumbColor: widget.accent,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          onChanged: (val) async {
            if (val) {
              await NotificationService.instance.requestPermissions();
              // Rebuild either way: on a denial the switch must snap back
              // rather than sit in the "on" position with nothing scheduled.
              if (mounted) setState(() {});
            } else {
              await NotificationService.instance.setNotificationsEnabled(false);
              if (mounted) setState(() {});
            }
          },
        ),
      ],
    );
  }
}
