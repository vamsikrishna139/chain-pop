import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/review/review_coordinator.dart';
import '../../theme/app_colors.dart';

enum ReviewPromptAction {
  rate,
  later,
  never,
}

/// In-game soft pre-prompt modal for Chain Pop store ratings.
///
/// Designed to strictly follow Apple App Store Guideline 5.6.1 and Google Play
/// In-App Review API rules:
/// - Purely neutral request (no sentiment screening, no "like the app?" filter).
/// - 3 explicit options: Rate Now, Later (14-day cooldown), Never (permanent suppression).
/// - Smooth exit returning cleanly to the victory screen.
class ReviewSoftPromptSheet extends StatelessWidget {
  final int level;
  final ReviewCoordinator coordinator;
  final Color accent;

  const ReviewSoftPromptSheet({
    super.key,
    required this.level,
    required this.coordinator,
    this.accent = AppColors.starGold,
  });

  /// Displays the soft prompt modal as a bottom sheet.
  static Future<void> show({
    required BuildContext context,
    required int level,
    required ReviewCoordinator coordinator,
    Color accent = AppColors.starGold,
  }) async {
    unawaited(coordinator.onPromptShown(level: level));

    final action = await showModalBottomSheet<ReviewPromptAction>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return ReviewSoftPromptSheet(
          level: level,
          coordinator: coordinator,
          accent: accent,
        );
      },
    );

    switch (action) {
      case ReviewPromptAction.rate:
        await coordinator.onRateTapped(level: level);
        break;
      case ReviewPromptAction.later:
      case null: // Outside tap or hardware back
        await coordinator.onLaterTapped(level: level);
        break;
      case ReviewPromptAction.never:
        await coordinator.onNeverTapped(level: level);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.12),
            blurRadius: 40,
            offset: const Offset(0, -10),
          ),
        ],
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header icon
              Center(
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent.withValues(alpha: 0.15),
                    border: Border.all(
                      color: accent.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                  ),
                  child: Icon(
                    Icons.star_rounded,
                    color: accent,
                    size: 32,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Title
              Text(
                'ENJOYING CHAIN POP?',
                textAlign: TextAlign.center,
                style: GoogleFonts.jetBrainsMono(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 10),

              // Description
              Text(
                'Player reviews help us build new puzzle worlds, refine challenge balance, and keep the game ad-light.',
                textAlign: TextAlign.center,
                style: GoogleFonts.rajdhani(
                  color: Colors.white70,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 24),

              // Rate Now button (Primary)
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop(ReviewPromptAction.rate);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  'RATE CHAIN POP',
                  style: GoogleFonts.jetBrainsMono(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Remind Me Later button (Secondary)
              OutlinedButton(
                onPressed: () {
                  Navigator.of(context).pop(ReviewPromptAction.later);
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'REMIND ME LATER',
                  style: GoogleFonts.jetBrainsMono(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Don't Ask Again (Never)
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(ReviewPromptAction.never);
                },
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white38,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
                child: Text(
                  "DON'T ASK AGAIN",
                  style: GoogleFonts.jetBrainsMono(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
}
