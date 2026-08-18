import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../game/levels/generation/difficulty_mode.dart';
import '../../../models/difficulty.dart';
import '../../../theme/app_colors.dart';
import '../game_screen_constants.dart';
import 'timer_pause_chip.dart';


class GameHeaderHud extends StatelessWidget {
  final Key? measureKey;
  final VoidCallback onBack;
  final VoidCallback onOpenSettings;
  final int livesRemaining;
  final DifficultyMode difficulty;
  final String? headerModeLabel;
  final String? missionLabel;
  final int removedNodes;
  final int totalNodes;
  final int? coresRestored;
  final int? totalCores;
  final int? networkIntegrity;
  final int? timeLeftSec;
  final int? timeLimitSec;
  final Duration elapsed;
  final VoidCallback onTogglePause;
  int get maxLives => GameScreenConstants.maxLives;
  final String? sessionGoalLabel;
  final int? sessionGoalProgress;
  final int? sessionGoalTarget;

  const GameHeaderHud({
    super.key,
    this.measureKey,
    required this.onBack,
    required this.onOpenSettings,
    required this.livesRemaining,
    required this.difficulty,
    this.headerModeLabel,
    this.missionLabel,
    required this.removedNodes,
    required this.totalNodes,
    this.coresRestored,
    this.totalCores,
    this.networkIntegrity,
    required this.timeLeftSec,
    required this.timeLimitSec,
    required this.elapsed,
    required this.onTogglePause,
    this.sessionGoalLabel,
    this.sessionGoalProgress,
    this.sessionGoalTarget,
  });

  @override
  Widget build(BuildContext context) {
    final accent = difficulty.color;
    final usesCores = (totalCores ?? 0) > 0;
    
    final titleText = headerModeLabel ?? difficulty.label.toUpperCase();
    final directiveText = missionLabel;

    final remaining = usesCores
        ? ((totalCores ?? 0) - (coresRestored ?? 0)).clamp(0, 999)
        : (totalNodes - removedNodes).clamp(0, 999);

    return SafeArea(
      child: Padding(
        key: measureKey,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Clean Primary Navigation Bar
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Left Side: Back + Title + Directive Pill
                Expanded(
                  child: Row(
                    children: [
                      // Dedicated Back Action
                      InkWell(
                        onTap: onBack,
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                          ),
                          child: const Icon(Icons.arrow_back_rounded, size: 16, color: Colors.white70),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Level Title (No truncation)
                      Flexible(
                        child: Text(
                          titleText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.rajdhani(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.0,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      if (directiveText != null) ...[
                        const SizedBox(width: 8),
                        // Sleek Directive Pill
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: accent.withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              directiveText.toUpperCase(),
                              maxLines: 1,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: accent,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Right Side: Timer + Settings
                Row(
                  children: [
                    // Integrated Timer & Pause
                    TimerPauseChip(
                      timeLeftSec: timeLeftSec,
                      timeLimitSec: timeLimitSec,
                      elapsed: elapsed,
                      color: accent,
                      onTap: onTogglePause,
                    ),
                    const SizedBox(width: 8),
                    // Settings Action
                    InkWell(
                      onTap: onOpenSettings,
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                        ),
                        child: const Icon(Icons.tune_rounded, size: 16, color: Colors.white70),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            
            const SizedBox(height: 10),

            // Unified Telemetry Capsule Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Lives / Integrity
                  Row(
                    children: [
                      Text(
                        'LIVES',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          color: Colors.white54,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Row(
                        children: List.generate(maxLives, (i) {
                          final hasLife = i < livesRemaining;
                          return Container(
                            margin: const EdgeInsets.only(right: 5),
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: hasLife ? Colors.redAccent : Colors.white.withValues(alpha: 0.1),
                              boxShadow: hasLife ? [BoxShadow(color: Colors.redAccent.withValues(alpha: 0.6), blurRadius: 6)] : [],
                            ),
                          );
                        }),
                      ),
                    ],
                  ),
                  
                  // Mission Objective (REMAINING 18)
                  RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: usesCores ? 'CORES ' : 'REMAINING ',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            color: Colors.white54,
                          ),
                        ),
                        TextSpan(
                          text: usesCores
                              ? '${coresRestored ?? 0}/${totalCores ?? 0}'
                              : '$remaining',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Session Directive Banner
            if (sessionGoalLabel != null && sessionGoalLabel!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A26),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.bolt_rounded,
                          size: 14,
                          color: Colors.cyanAccent,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          sessionGoalLabel!,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                    if (sessionGoalTarget != null && sessionGoalTarget! > 0)
                      Text(
                        '${sessionGoalProgress ?? 0}/$sessionGoalTarget',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
