import 'dart:async';

import 'package:flutter/material.dart';

import '../../../game/levels/generation/difficulty_mode.dart';
import '../../../models/difficulty.dart';
import '../../../theme/app_colors.dart';
import '../../../utils/progress_format.dart';
import '../game_screen_constants.dart';

class WinPanel extends StatefulWidget {
  final int levelId;
  final DifficultyMode difficulty;
  final int stars;
  final int foulCount;
  final Duration timeTaken;
  final int autoAdvanceSec;
  final VoidCallback onMenu;
  final VoidCallback onRetry;
  final VoidCallback onNext;

  const WinPanel({
    super.key,
    required this.levelId,
    required this.difficulty,
    required this.stars,
    required this.foulCount,
    required this.timeTaken,
    required this.autoAdvanceSec,
    required this.onMenu,
    required this.onRetry,
    required this.onNext,
  });

  @override
  State<WinPanel> createState() => _WinPanelState();
}

class _WinPanelState extends State<WinPanel> with TickerProviderStateMixin {
  late final List<AnimationController> _starCtrl;
  late final List<Animation<double>> _starScale;
  late final List<Timer> _starStartTimers;

  @override
  void initState() {
    super.initState();
    _starCtrl = List.generate(3, (i) {
      return AnimationController(
        vsync: this,
        duration: const Duration(
          milliseconds: GameScreenConstants.winStarAnimationMs,
        ),
      );
    });
    _starStartTimers = List.generate(3, (i) {
      return Timer(
        Duration(
          milliseconds: GameScreenConstants.winStarStaggerBaseMs +
              i * GameScreenConstants.winStarStaggerStepMs,
        ),
        () {
          if (mounted) _starCtrl[i].forward();
        },
      );
    });
    _starScale = _starCtrl
        .map(
          (c) => Tween<double>(begin: 0.0, end: 1.0).animate(
            CurvedAnimation(parent: c, curve: Curves.elasticOut),
          ),
        )
        .toList();
  }

  @override
  void dispose() {
    for (final timer in _starStartTimers) {
      timer.cancel();
    }
    for (final c in _starCtrl) {
      c.dispose();
    }
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.difficulty.color;
    final totalSec = GameScreenConstants.winAutoAdvanceSeconds;
    final frac = widget.autoAdvanceSec / totalSec;

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: accent.withOpacity(0.3), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: accent.withOpacity(0.2),
              blurRadius: 40,
              spreadRadius: 4,
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'LEVEL ${ProgressFormat.level(widget.levelId)} · ${widget.difficulty.label}',
              style: TextStyle(
                color: accent,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Complete!',
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(3, (i) {
                final earned = i < widget.stars;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: ScaleTransition(
                    scale: _starScale[i],
                    child: Icon(
                      earned ? Icons.star_rounded : Icons.star_outline_rounded,
                      size: 50,
                      color: earned ? AppColors.starGold : Colors.white24,
                      shadows: earned
                          ? [
                              Shadow(
                                color: AppColors.starGold.withOpacity(0.7),
                                blurRadius: 16,
                              )
                            ]
                          : [],
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _WinStatChip(label: 'TIME', value: _fmt(widget.timeTaken)),
                const SizedBox(width: 16),
                _WinStatChip(
                  label: 'FOULS',
                  value: '${widget.foulCount}',
                ),
              ],
            ),
            const SizedBox(height: 20),
            Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.skip_next_rounded,
                      size: 14,
                      color: Colors.white38,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Next level in ${widget.autoAdvanceSec}s',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: frac.clamp(0.0, 1.0),
                    backgroundColor: Colors.white12,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      accent.withOpacity(0.6),
                    ),
                    minHeight: 3,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _WinOutlineButton(
                    label: 'MENU',
                    icon: Icons.home_rounded,
                    onPressed: widget.onMenu,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _WinOutlineButton(
                    label: 'RETRY',
                    icon: Icons.refresh_rounded,
                    onPressed: widget.onRetry,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: _WinPrimaryButton(
                    label: 'NEXT',
                    icon: Icons.arrow_forward_rounded,
                    color: accent,
                    onPressed: widget.onNext,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WinStatChip extends StatelessWidget {
  final String label;
  final String value;

  const _WinStatChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 10,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _WinOutlineButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  const _WinOutlineButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 15, color: Colors.white38),
      label: Text(
        label,
        style: const TextStyle(
          color: Colors.white38,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1,
        ),
      ),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Colors.white12),
        ),
      ),
    );
  }
}

class _WinPrimaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  const _WinPrimaryButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(
        label,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.black,
        padding: const EdgeInsets.symmetric(vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 8,
        shadowColor: color.withOpacity(0.5),
      ),
    );
  }
}
