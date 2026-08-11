import 'package:flutter/material.dart';

import '../../../models/game_settings.dart';
import '../../../theme/app_colors.dart';
import '../../widgets/privacy_ads_settings_section.dart';

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


      return StatefulBuilder(
        builder: (context, setModalState) {

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
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Aim Guide',
                      style: TextStyle(color: Colors.white70),
                    ),
                    subtitle: const Text(
                      'Show a node’s exit path while you press',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                    value: current.showAimRay,
                    activeThumbColor: accent,
                    onChanged: (v) {
                      current = current.copyWith(showAimRay: v);
                      onSettingsChanged(current);
                      setModalState(() {});
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Ambient Motion',
                      style: TextStyle(color: Colors.white70),
                    ),
                    subtitle: const Text(
                      'Enable slow background drift animations',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                    value: current.ambientMotion,
                    activeThumbColor: accent,
                    onChanged: (v) {
                      current = current.copyWith(ambientMotion: v);
                      onSettingsChanged(current);
                      setModalState(() {});
                    },
                  ),
                  const Divider(color: Colors.white10, height: 32),
                  PrivacyAdsSettingsSection(accent: accent),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
