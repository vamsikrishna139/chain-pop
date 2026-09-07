import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'privacy_ads_settings_section.dart';
import 'purchases_settings_section.dart';

/// Bottom sheet for home screen options (purchases, privacy, ads).
Future<void> showHomeSettingsSheet({
  required BuildContext context,
  required Color accent,
  VoidCallback? onResetGameData,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFF14141C),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
          ),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.1),
              blurRadius: 40,
              offset: const Offset(0, -10),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.tune_rounded, color: accent, size: 20),
                        const SizedBox(width: 10),
                        Text(
                          'SETTINGS',
                          style: GoogleFonts.jetBrainsMono(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close_rounded,
                            size: 16, color: Colors.white70),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Divider(color: Colors.white.withValues(alpha: 0.1)),
                const SizedBox(height: 16),

                // Content
                PurchasesSettingsSection(accent: accent),
                const SizedBox(height: 16),
                PrivacyAdsSettingsSection(accent: accent),
                if (onResetGameData != null) ...[
                  const SizedBox(height: 16),
                  Divider(color: Colors.white.withValues(alpha: 0.1)),
                  const SizedBox(height: 8),
                  _ResetGameDataTile(
                    onPressed: () {
                      // Close the sheet first so the confirmation dialog owns
                      // the screen and the caller's setState targets a live
                      // route.
                      Navigator.pop(sheetContext);
                      onResetGameData();
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// Destructive "Reset Game Data" row for the settings sheet.
///
/// The privacy policy names this as a user control, so it must be reachable
/// without knowing the long-press shortcut on the play button.
class _ResetGameDataTile extends StatelessWidget {
  final VoidCallback onPressed;

  const _ResetGameDataTile({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return TextButton.icon(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      ),
      icon: Icon(Icons.restart_alt_rounded, color: error, size: 18),
      label: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Reset Game Data',
          style: GoogleFonts.rajdhani(
            color: error,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}
