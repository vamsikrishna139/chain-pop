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
  final String? missionLabel;
  final String? sessionGoalLabel;
  final int? sessionGoalProgress;
  final int? sessionGoalTarget;
  final bool? sessionGoalComplete;
  final int autoAdvanceSec;
  final VoidCallback onMenu;
  final VoidCallback onRetry;
  final VoidCallback onNext;

  /// When false, hides auto-advance copy and the Next button (daily puzzle).
  final bool showNextAndAutoAdvance;

  /// Replaces the default `LEVEL … · MODE` caption when non-null.
  final String? titleLine;

  /// When non-null, shown in the WinPanel (e.g. 'DIRECTIVE: FLAWLESS')
  final String? directiveLabel;

  const WinPanel({
    super.key,
    required this.levelId,
    required this.difficulty,
    required this.stars,
    required this.foulCount,
    required this.timeTaken,
    this.missionLabel,
    this.sessionGoalLabel,
    this.sessionGoalProgress,
    this.sessionGoalTarget,
    this.sessionGoalComplete,
    required this.autoAdvanceSec,
    required this.onMenu,
    required this.onRetry,
    required this.onNext,
    this.showNextAndAutoAdvance = true,
    this.titleLine,
    this.directiveLabel,
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
    const totalSec = GameScreenConstants.winAutoAdvanceSeconds;
    final frac = widget.autoAdvanceSec / totalSec;

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: accent.withValues(alpha: 0.3), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.2),
              blurRadius: 40,
              spreadRadius: 4,
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                widget.titleLine ??
                    'LEVEL ${ProgressFormat.level(widget.levelId)} · ${widget.difficulty.label}',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                ),
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
            if (widget.directiveLabel != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.directiveLabel!,
                        maxLines: 1,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                      if (widget.missionLabel != null) ...[
                        const Text(
                          ' · ',
                          maxLines: 1,
                          style: TextStyle(
                            color: Colors.white24,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                        Text(
                          widget.missionLabel!,
                          maxLines: 1,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
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
                                color:
                                    AppColors.starGold.withValues(alpha: 0.7),
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
            if (widget.sessionGoalLabel != null) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(
                    widget.sessionGoalComplete == true
                        ? Icons.check_circle_rounded
                        : Icons.flag_rounded,
                    size: 13,
                    color: widget.sessionGoalComplete == true
                        ? const Color(0xFF00FF87)
                        : accent,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.sessionGoalLabel!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (widget.sessionGoalComplete == true)
                    const Text(
                      'COMPLETE',
                      style: TextStyle(
                        color: Color(0xFF00FF87),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    )
                  else ...[
                    SizedBox(
                      width: 48,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: (widget.sessionGoalTarget ?? 1) == 0
                              ? 0.0
                              : (widget.sessionGoalProgress ?? 0) /
                                  widget.sessionGoalTarget!,
                          backgroundColor: Colors.white.withValues(alpha: 0.1),
                          color: accent,
                          minHeight: 4,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${widget.sessionGoalProgress}/${widget.sessionGoalTarget}',
                      style: TextStyle(
                        color: accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ],
              ),
            ],
            if (widget.showNextAndAutoAdvance) ...[
              const SizedBox(height: 20),
              Semantics(
                liveRegion: true,
                label:
                    'Next level in ${widget.autoAdvanceSec} seconds. Tap Next to skip the wait.',
                child: Column(
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
                          accent.withValues(alpha: 0.6),
                        ),
                        minHeight: 3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            SizedBox(height: widget.showNextAndAutoAdvance ? 20 : 8),
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
                if (widget.showNextAndAutoAdvance) ...[
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
        color: Colors.white.withValues(alpha: 0.06),
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
        shadowColor: color.withValues(alpha: 0.5),
      ),
    );
  }
}
