import 'package:flutter/material.dart';

import '../../../game/levels/generation/difficulty_mode.dart';
import '../../../models/difficulty.dart';
import '../../../theme/app_colors.dart';

class TimeUpDialog extends StatelessWidget {
  final DifficultyMode difficulty;
  final VoidCallback onRetry;
  final VoidCallback onMenu;

  const TimeUpDialog({
    super.key,
    required this.difficulty,
    required this.onRetry,
    required this.onMenu,
  });

  @override
  Widget build(BuildContext context) {
    final accent = difficulty.color;
    return AlertDialog(
      backgroundColor: AppColors.surfaceDialog,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: accent.withOpacity(0.3)),
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
        style: TextStyle(color: Colors.white.withOpacity(0.6)),
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
      ],
    );
  }
}

class GameOverDialog extends StatelessWidget {
  final DifficultyMode difficulty;
  final VoidCallback onRetry;
  final VoidCallback onMenu;

  const GameOverDialog({
    super.key,
    required this.difficulty,
    required this.onRetry,
    required this.onMenu,
  });

  @override
  Widget build(BuildContext context) {
    final accent = difficulty.color;
    return AlertDialog(
      backgroundColor: AppColors.surfaceDialog,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: Colors.redAccent.withOpacity(0.3)),
      ),
      title: Column(
        children: [
          Icon(
            Icons.favorite_rounded,
            color: Colors.redAccent.withOpacity(0.4),
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
        style: TextStyle(color: Colors.white.withOpacity(0.6)),
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
      ],
    );
  }
}
