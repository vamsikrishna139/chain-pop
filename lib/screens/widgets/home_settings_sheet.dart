import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'privacy_ads_settings_section.dart';
import 'purchases_settings_section.dart';

/// Bottom sheet for home screen options (purchases, privacy, ads).
Future<void> showHomeSettingsSheet({
  required BuildContext context,
  required Color accent,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surfaceDialog,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Settings',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.95),
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 24),
              PurchasesSettingsSection(accent: accent),
              PrivacyAdsSettingsSection(accent: accent),
            ],
          ),
        ),
      );
    },
  );
}
