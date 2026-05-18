import 'package:flutter/material.dart';

import '../../../game/levels/generation/difficulty_mode.dart';
import '../../../models/difficulty.dart';
import '../../../theme/app_colors.dart';

class TimeUpDialog extends StatelessWidget {
  final DifficultyMode difficulty;
  final VoidCallback onRetry;
  final VoidCallback onMenu;
  final bool showRewardedContinue;
  final bool rewardedAdReady;
  final Future<void> Function()? onWatchAdContinue;

  const TimeUpDialog({
    super.key,
    required this.difficulty,
    required this.onRetry,
    required this.onMenu,
    this.showRewardedContinue = false,
    this.rewardedAdReady = false,
    this.onWatchAdContinue,
  });

  @override
  Widget build(BuildContext context) {
    final accent = difficulty.color;
    return AlertDialog(
      backgroundColor: AppColors.surfaceDialog,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: accent.withValues(alpha: 0.3)),
      ),
      title: Column(
        children: [
          Icon(Icons.timer_off_rounded, color: accent, size: 48),
          const SizedBox(height: 12),
          const Text(
            "TIME'S UP!",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
      content: Text(
        'The clock ran out. Try again?',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: onMenu,
          child: const Text('MENU', style: TextStyle(color: Colors.white38)),
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text(
            'RETRY',
            style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        if (showRewardedContinue && onWatchAdContinue != null) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed:
                  rewardedAdReady ? () async => onWatchAdContinue!() : null,
              icon: Icon(
                Icons.play_circle_outline_rounded,
                color: rewardedAdReady ? accent : Colors.white24,
              ),
              label: Text(
                rewardedAdReady ? 'WATCH AD TO CONTINUE' : 'AD LOADING…',
                style: TextStyle(
                  color: rewardedAdReady ? accent : Colors.white24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Confirms rewarded unlock before opening a past daily puzzle from the calendar.
class PastDailyUnlockDialog extends StatelessWidget {
  final Color accent;
  final String puzzleDateLabel;
  final VoidCallback onCancel;
  final VoidCallback onWatchAd;

  const PastDailyUnlockDialog({
    super.key,
    required this.accent,
    required this.puzzleDateLabel,
    required this.onCancel,
    required this.onWatchAd,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceDialog,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: accent.withValues(alpha: 0.35)),
      ),
      title: Column(
        children: [
          Icon(Icons.schedule_rounded, color: accent, size: 44),
          const SizedBox(height: 10),
          const Text(
            'TIME TRAVEL',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
      content: Text(
        'Jump back to $puzzleDateLabel?\n\n'
        "Watch a short ad to unlock this day's challenge. You only need to do this once per date.",
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.72),
          height: 1.35,
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: onCancel,
          child: const Text(
            'NOT NOW',
            style:
                TextStyle(color: Colors.white38, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: onWatchAd,
          icon: const Icon(Icons.play_circle_outline_rounded, size: 20),
          label: const Text(
            'WATCH AD',
            style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.8),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }
}

class GameOverDialog extends StatelessWidget {
  final DifficultyMode difficulty;
  final VoidCallback onRetry;
  final VoidCallback onMenu;
  final bool showRewardedContinue;
  final bool rewardedAdReady;
  final Future<void> Function()? onWatchAdContinue;

  const GameOverDialog({
    super.key,
    required this.difficulty,
    required this.onRetry,
    required this.onMenu,
    this.showRewardedContinue = false,
    this.rewardedAdReady = false,
    this.onWatchAdContinue,
  });

  @override
  Widget build(BuildContext context) {
    final accent = difficulty.color;
    return AlertDialog(
      backgroundColor: AppColors.surfaceDialog,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.3)),
      ),
      title: Column(
        children: [
          Icon(
            Icons.favorite_rounded,
            color: Colors.redAccent.withValues(alpha: 0.4),
            size: 48,
          ),
          const SizedBox(height: 12),
          const Text(
            'OUT OF LIVES',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
      content: Text(
        'You ran out of lives. Try again?',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: onMenu,
          child: const Text('MENU', style: TextStyle(color: Colors.white38)),
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text(
            'RETRY',
            style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        if (showRewardedContinue && onWatchAdContinue != null) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed:
                  rewardedAdReady ? () async => onWatchAdContinue!() : null,
              icon: Icon(
                Icons.play_circle_outline_rounded,
                color: rewardedAdReady ? accent : Colors.white24,
              ),
              label: Text(
                rewardedAdReady ? 'WATCH AD TO CONTINUE' : 'AD LOADING…',
                style: TextStyle(
                  color: rewardedAdReady ? accent : Colors.white24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
