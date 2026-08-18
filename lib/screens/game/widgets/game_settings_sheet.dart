import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../models/game_settings.dart';

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
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (context, setModalState) {
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
                            child: const Icon(Icons.close_rounded, size: 16, color: Colors.white70),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Divider(color: Colors.white.withValues(alpha: 0.1)),
                    const SizedBox(height: 16),
                    
                    Text(
                      'GAME TOGGLES',
                      style: GoogleFonts.jetBrainsMono(
                        color: accent,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    
                    _buildToggle(
                      title: 'Sound Effects',
                      subtitle: 'Harmonic node chimes & feedback',
                      icon: Icons.volume_up_rounded,
                      iconColor: Colors.greenAccent,
                      value: current.soundEnabled,
                      onChanged: (v) {
                        current = current.copyWith(soundEnabled: v);
                        onSettingsChanged(current);
                        setModalState(() {});
                      },
                    ),
                    const SizedBox(height: 8),
                    _buildToggle(
                      title: 'Haptic Vibration',
                      subtitle: 'Tactile impulses on release & fouls',
                      icon: Icons.vibration_rounded,
                      iconColor: accent,
                      value: current.hapticsEnabled,
                      onChanged: (v) {
                        current = current.copyWith(hapticsEnabled: v);
                        onSettingsChanged(current);
                        setModalState(() {});
                      },
                    ),
                    const SizedBox(height: 8),
                    _buildToggle(
                      title: 'High Contrast Palette',
                      subtitle: 'Okabe-Ito colorblind-safe node tokens',
                      icon: Icons.remove_red_eye_rounded,
                      iconColor: Colors.cyanAccent,
                      value: current.colorblindFriendly,
                      onChanged: (v) {
                        current = current.copyWith(colorblindFriendly: v);
                        onSettingsChanged(current);
                        setModalState(() {});
                      },
                    ),
                    const SizedBox(height: 8),
                    _buildToggle(
                      title: 'Trajectory Aim Guides',
                      subtitle: 'Subtle exit axis projection lines',
                      icon: Icons.explore_rounded,
                      iconColor: Colors.amberAccent,
                      value: current.showAimRay,
                      onChanged: (v) {
                        current = current.copyWith(showAimRay: v);
                        onSettingsChanged(current);
                        setModalState(() {});
                      },
                    ),
                    const SizedBox(height: 8),
                    _buildToggle(
                      title: 'Ambient Glow & Motion',
                      subtitle: 'Subtle background particle pulses',
                      icon: Icons.auto_awesome_rounded,
                      iconColor: Colors.purpleAccent,
                      value: current.ambientMotion,
                      onChanged: (v) {
                        current = current.copyWith(ambientMotion: v);
                        onSettingsChanged(current);
                        setModalState(() {});
                      },
                    ),
                    
                    const SizedBox(height: 16),
                    Divider(color: Colors.white.withValues(alpha: 0.1)),
                    const SizedBox(height: 16),
                    
                    PrivacyAdsSettingsSection(accent: accent),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

Widget _buildToggle({
  required String title,
  required String subtitle,
  required IconData icon,
  required Color iconColor,
  required bool value,
  required ValueChanged<bool> onChanged,
}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: const Color(0xFF1A1A22),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
    ),
    child: Row(
      children: [
        Icon(icon, size: 20, color: value ? iconColor : Colors.white24),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.rajdhani(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: GoogleFonts.jetBrainsMono(
                  color: Colors.white54,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: Colors.white,
          activeTrackColor: Colors.green,
          inactiveThumbColor: Colors.white,
          inactiveTrackColor: Colors.grey[800],
        ),
      ],
    ),
  );
}
