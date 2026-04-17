import 'package:flutter/material.dart';

import '../../../game/levels/generation/difficulty_mode.dart';
import '../../../models/difficulty.dart';
import 'difficulty_label.dart';
import 'lives_display.dart';
import 'timer_pause_chip.dart';

class GameHeaderHud extends StatelessWidget {
  /// Placed on the inner [Padding] so [RenderBox] height matches stacked HUD.
  final Key? measureKey;
  final VoidCallback onBack;
  final VoidCallback onOpenSettings;
  final int livesRemaining;
  final DifficultyMode difficulty;
  /// When non-null, shown instead of [DifficultyLabel] (e.g. daily challenge).
  final String? headerModeLabel;
  final int removedNodes;
  final int totalNodes;
  final int? timeLeftSec;
  final int? timeLimitSec;
  final Duration elapsed;
  final VoidCallback onTogglePause;

  const GameHeaderHud({
    super.key,
    this.measureKey,
    required this.onBack,
    required this.onOpenSettings,
    required this.livesRemaining,
    required this.difficulty,
    this.headerModeLabel,
    required this.removedNodes,
    required this.totalNodes,
    required this.timeLeftSec,
    required this.timeLimitSec,
    required this.elapsed,
    required this.onTogglePause,
  });

  @override
  Widget build(BuildContext context) {
    final accent = difficulty.color;
    final progress = totalNodes > 0 ? removedNodes / totalNodes : 0.0;

    return SafeArea(
      child: Padding(
        key: measureKey,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: onBack,
                  behavior: HitTestBehavior.opaque,
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(
                      Icons.chevron_left_rounded,
                      color: Colors.white70,
                      size: 28,
                    ),
                  ),
                ),
                const Spacer(),
                const SizedBox.shrink(),
                const Spacer(),
                IconButton(
                  onPressed: onOpenSettings,
                  tooltip: 'Settings',
                  icon: Icon(
                    Icons.tune_rounded,
                    color: Colors.white.withOpacity(0.72),
                    size: 26,
                  ),
                ),
                const SizedBox(width: 2),
                LivesDisplay(livesRemaining: livesRemaining),
              ],
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  if (headerModeLabel != null)
                    Text(
                      headerModeLabel!,
                      style: TextStyle(
                        color: accent,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                      ),
                    )
                  else
                    DifficultyLabel(difficulty: difficulty),
                  const Spacer(),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$removedNodes / $totalNodes nodes',
                        style: TextStyle(
                          color: accent.withOpacity(0.7),
                          fontSize: 11,
                          letterSpacing: 1,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: 80,
                        height: 3,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: progress.clamp(0.0, 1.0),
                            backgroundColor: Colors.white12,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              accent.withOpacity(0.7),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  TimerPauseChip(
                    timeLeftSec: timeLeftSec,
                    timeLimitSec: timeLimitSec,
                    elapsed: elapsed,
                    color: accent,
                    onTap: onTogglePause,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
