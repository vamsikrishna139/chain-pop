import 'dart:async';

import 'package:flutter/material.dart';

import '../../../game/levels/generation/difficulty_mode.dart';
import '../../../models/difficulty.dart';
import '../../../theme/app_colors.dart';

IconData _continueIcon(bool isPremium) =>
    isPremium ? Icons.play_arrow_rounded : Icons.play_circle_outline_rounded;

String _continueLabel({
  required bool isPremium,
  required bool rewardedAdReady,
  bool gaveUp = false,
}) {
  if (isPremium) return 'CONTINUE';
  if (rewardedAdReady) return 'WATCH AD TO CONTINUE';
  return gaveUp ? 'AD UNAVAILABLE' : 'AD LOADING…';
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

/// Time-out: retry, menu, or a rewarded continue with bonus seconds.
class TimeUpDialog extends StatelessWidget {
  final DifficultyMode difficulty;
  final VoidCallback onRetry;
  final VoidCallback onMenu;
  final bool showRewardedContinue;

  /// Readiness when the dialog opened. Superseded by [rewardedReadyProbe].
  final bool rewardedAdReady;

  /// Re-checked while the dialog is open so a rewarded ad that finishes
  /// loading after the dialog appears still enables the button.
  final bool Function()? rewardedReadyProbe;
  final Future<void> Function()? onWatchAdContinue;

  /// Premium users continue without an ad, so the button drops the ad copy.
  final bool isPremium;

  const TimeUpDialog({
    super.key,
    required this.difficulty,
    required this.onRetry,
    required this.onMenu,
    this.showRewardedContinue = false,
    this.rewardedAdReady = false,
    this.rewardedReadyProbe,
    this.onWatchAdContinue,
    this.isPremium = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = difficulty.color;
    return _LevelFailedDialog(
      accent: accent,
      borderColor: accent,
      icon: Icon(Icons.timer_off_rounded, color: accent, size: 48),
      title: "TIME'S UP!",
      message: 'The clock ran out. Try again?',
      onRetry: onRetry,
      onMenu: onMenu,
      showRewardedContinue: showRewardedContinue,
      rewardedAdReady: rewardedAdReady,
      rewardedReadyProbe: rewardedReadyProbe,
      onWatchAdContinue: onWatchAdContinue,
      isPremium: isPremium,
    );
  }
}

/// Out of lives: retry, menu, or a rewarded continue with one life back.
class GameOverDialog extends StatelessWidget {
  final DifficultyMode difficulty;
  final VoidCallback onRetry;
  final VoidCallback onMenu;
  final bool showRewardedContinue;

  /// Readiness when the dialog opened. Superseded by [rewardedReadyProbe].
  final bool rewardedAdReady;

  /// Re-checked while the dialog is open (see [TimeUpDialog]).
  final bool Function()? rewardedReadyProbe;
  final Future<void> Function()? onWatchAdContinue;

  /// Premium users continue without an ad, so the button drops the ad copy.
  final bool isPremium;

  const GameOverDialog({
    super.key,
    required this.difficulty,
    required this.onRetry,
    required this.onMenu,
    this.showRewardedContinue = false,
    this.rewardedAdReady = false,
    this.rewardedReadyProbe,
    this.onWatchAdContinue,
    this.isPremium = false,
  });

  @override
  Widget build(BuildContext context) {
    return _LevelFailedDialog(
      accent: difficulty.color,
      borderColor: Colors.redAccent,
      icon: Icon(
        Icons.favorite_rounded,
        color: Colors.redAccent.withValues(alpha: 0.4),
        size: 48,
      ),
      title: 'OUT OF LIVES',
      message: 'You ran out of lives. Try again?',
      onRetry: onRetry,
      onMenu: onMenu,
      showRewardedContinue: showRewardedContinue,
      rewardedAdReady: rewardedAdReady,
      rewardedReadyProbe: rewardedReadyProbe,
      onWatchAdContinue: onWatchAdContinue,
      isPremium: isPremium,
    );
  }
}

/// Shared body for [TimeUpDialog] and [GameOverDialog]: one stacked column of
/// full-width actions (retry, rewarded continue, menu).
class _LevelFailedDialog extends StatelessWidget {
  final Color accent;
  final Color borderColor;
  final Widget icon;
  final String title;
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onMenu;
  final bool showRewardedContinue;
  final bool rewardedAdReady;
  final bool Function()? rewardedReadyProbe;
  final Future<void> Function()? onWatchAdContinue;
  final bool isPremium;

  const _LevelFailedDialog({
    required this.accent,
    required this.borderColor,
    required this.icon,
    required this.title,
    required this.message,
    required this.onRetry,
    required this.onMenu,
    required this.showRewardedContinue,
    required this.rewardedAdReady,
    required this.rewardedReadyProbe,
    required this.onWatchAdContinue,
    required this.isPremium,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceDialog,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: borderColor.withValues(alpha: 0.3)),
      ),
      title: Column(
        children: [
          icon,
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
      content: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
      ),
      actions: [
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            if (showRewardedContinue && onWatchAdContinue != null) ...[
              const SizedBox(height: 10),
              _RewardedContinueButton(
                accent: accent,
                isPremium: isPremium,
                initiallyReady: rewardedAdReady,
                readyProbe: rewardedReadyProbe,
                onPressed: onWatchAdContinue!,
              ),
            ],
            const SizedBox(height: 4),
            TextButton(
              onPressed: onMenu,
              child:
                  const Text('MENU', style: TextStyle(color: Colors.white54)),
            ),
          ],
        ),
      ],
    );
  }
}

/// Rewarded-continue button that keeps polling ad readiness while visible.
///
/// The dialog used to snapshot `isRewardedReady` once at open, so an ad that
/// finished loading a moment later left the button disabled on "AD LOADING…"
/// for good. After [_giveUpAfter] with no ad it says so instead of spinning.
class _RewardedContinueButton extends StatefulWidget {
  final Color accent;
  final bool isPremium;
  final bool initiallyReady;
  final bool Function()? readyProbe;
  final Future<void> Function() onPressed;

  const _RewardedContinueButton({
    required this.accent,
    required this.isPremium,
    required this.initiallyReady,
    required this.readyProbe,
    required this.onPressed,
  });

  @override
  State<_RewardedContinueButton> createState() =>
      _RewardedContinueButtonState();
}

class _RewardedContinueButtonState extends State<_RewardedContinueButton> {
  static const Duration _pollEvery = Duration(milliseconds: 500);
  static const Duration _giveUpAfter = Duration(seconds: 12);

  late bool _ready = widget.initiallyReady;
  bool _gaveUp = false;
  Timer? _poll;
  final Stopwatch _waited = Stopwatch()..start();

  @override
  void initState() {
    super.initState();
    if (!_ready && widget.readyProbe != null) {
      _poll = Timer.periodic(_pollEvery, (t) {
        if (!mounted) return t.cancel();
        final now = widget.readyProbe!();
        if (now) {
          t.cancel();
          setState(() => _ready = true);
        } else if (!_gaveUp && _waited.elapsed >= _giveUpAfter) {
          // Keep polling — a late fill still enables the button — but stop
          // promising it is about to load.
          setState(() => _gaveUp = true);
        }
      });
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = _ready ? widget.accent : Colors.white24;
    return OutlinedButton.icon(
      onPressed: _ready ? () async => widget.onPressed() : null,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(46),
        side: BorderSide(color: color.withValues(alpha: 0.6)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: Icon(_continueIcon(widget.isPremium), color: color),
      label: Text(
        _continueLabel(
          isPremium: widget.isPremium,
          rewardedAdReady: _ready,
          gaveUp: _gaveUp,
        ),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}
