import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/chain_pop_legal.dart';
import '../../../models/game_settings.dart';
import '../../../services/ads/ump_consent.dart';
import '../../../theme/app_colors.dart';
import 'privacy_rights_sheet.dart';

/// Bottom sheet for in-run sound / haptics / colorblind toggles.
Future<void> showGameSettingsSheet({
  required BuildContext context,
  required Color accent,
  required GameSettings settings,
  required void Function(GameSettings updated) onSettingsChanged,
}) {
  var current = settings;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surfaceDialog,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) {
      bool privacyOptionsRequired = false;
      bool hasCheckedPrivacy = false;

      return StatefulBuilder(
        builder: (context, setModalState) {
          if (!hasCheckedPrivacy) {
            hasCheckedPrivacy = true;
            isPrivacyOptionsRequired().then((val) {
              if (val) {
                if (context.mounted) {
                  setModalState(() => privacyOptionsRequired = true);
                }
              }
            });
          }
          Future<void> openPrivacyPolicy() async {
            final uri = Uri.parse(ChainPopLegal.privacyPolicyUrl);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          }

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
                  const SizedBox(height: 16),
                  Text(
                    'Game',
                    style: TextStyle(
                      color: accent,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Sound',
                      style: TextStyle(color: Colors.white70),
                    ),
                    value: current.soundEnabled,
                    activeThumbColor: accent,
                    onChanged: (v) {
                      current = current.copyWith(soundEnabled: v);
                      onSettingsChanged(current);
                      setModalState(() {});
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Haptics',
                      style: TextStyle(color: Colors.white70),
                    ),
                    value: current.hapticsEnabled,
                    activeThumbColor: accent,
                    onChanged: (v) {
                      current = current.copyWith(hapticsEnabled: v);
                      onSettingsChanged(current);
                      setModalState(() {});
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'High Contrast',
                      style: TextStyle(color: Colors.white70),
                    ),
                    value: current.colorblindFriendly,
                    activeThumbColor: accent,
                    onChanged: (v) {
                      current = current.copyWith(colorblindFriendly: v);
                      onSettingsChanged(current);
                      setModalState(() {});
                    },
                  ),
                  const Divider(color: Colors.white10, height: 32),
                  Text(
                    'Privacy & Ads',
                    style: TextStyle(
                      color: accent,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (privacyOptionsRequired)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          showPrivacyOptionsForm();
                        },
                        icon: Icon(
                          Icons.tune,
                          color: Colors.white70,
                          size: 18,
                        ),
                        label: Text(
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
                          accent: accent,
                          showAdChoicesButton: privacyOptionsRequired,
                        );
                      },
                      icon: Icon(
                        Icons.shield_outlined,
                        color: Colors.white70,
                        size: 18,
                      ),
                      label: Text(
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
                      onPressed: openPrivacyPolicy,
                      icon: Icon(
                        Icons.article_outlined,
                        color: Colors.white70,
                        size: 18,
                      ),
                      label: Text(
                        'Privacy policy',
                        style: TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
