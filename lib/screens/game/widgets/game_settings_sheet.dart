import 'package:flutter/material.dart';

import '../../../models/game_settings.dart';
import '../../../theme/app_colors.dart';

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
                      color: Colors.white.withOpacity(0.95),
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
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
                      'Colorblind palette',
                      style: TextStyle(color: Colors.white70),
                    ),
                    subtitle: Text(
                      'Higher-contrast hues (Okabe–Ito style)',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.45),
                        fontSize: 12,
                      ),
                    ),
                    value: current.colorblindFriendly,
                    activeThumbColor: accent,
                    onChanged: (v) {
                      current = current.copyWith(colorblindFriendly: v);
                      onSettingsChanged(current);
                      setModalState(() {});
                    },
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
