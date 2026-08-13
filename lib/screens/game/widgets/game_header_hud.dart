import 'package:flutter/material.dart';

import '../../../game/levels/generation/difficulty_mode.dart';
import '../../../models/difficulty.dart';
import 'difficulty_label.dart';
import 'lives_display.dart';
import 'phase_progress_bar.dart';
import 'timer_pause_chip.dart';

class GameHeaderHud extends StatelessWidget {
  /// Placed on the inner [Padding] so [RenderBox] height matches stacked HUD.
  final Key? measureKey;
  final VoidCallback onBack;
  final VoidCallback onOpenSettings;
  final int livesRemaining;
  final DifficultyMode difficulty;

  /// When non-null, shown instead of [DifficultyLabel] (e.g. daily incident).
  final String? headerModeLabel;

  /// Secondary line under mode label (world mission, incident objective).
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
  });

  @override
  Widget build(BuildContext context) {
    final accent = difficulty.color;
    final usesCores = (totalCores ?? 0) > 0;
    final progressLabel = usesCores
        ? 'Cores: ${coresRestored ?? 0}/${totalCores ?? 0}'
        : '$removedNodes / $totalNodes nodes';

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
                // Centered between back and settings. FittedBox scales the
                // label down on very narrow phones (≈320px) so the row never
                // overflows when Integrity shows alongside lives + cores.
                Expanded(
                  child: networkIntegrity == null
                      ? const SizedBox.shrink()
                      : Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              'Integrity: $networkIntegrity%',
                              maxLines: 1,
                              style: TextStyle(
                                color: _integrityColor(networkIntegrity!)
                                    .withValues(alpha: 0.9),
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),
                        ),
                ),
                IconButton(
                  onPressed: onOpenSettings,
                  tooltip: 'Settings',
                  icon: Icon(
                    Icons.tune_rounded,
                    color: Colors.white.withValues(alpha: 0.72),
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (headerModeLabel != null)
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              headerModeLabel!,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: accent,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.1,
                              ),
                            ),
                          )
                        else
                          DifficultyLabel(difficulty: difficulty),
                        if (missionLabel != null) ...[
                          const SizedBox(height: 2),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              missionLabel!,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.55),
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        progressLabel,
                        style: TextStyle(
                          color: accent.withValues(alpha: 0.7),
                          fontSize: 11,
                          letterSpacing: 1,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      PhaseProgressBar(
                        removedNodes: removedNodes,
                        totalNodes: totalNodes,
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),
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

  static Color _integrityColor(int value) {
    if (value >= 70) return const Color(0xFF00FF87);
    if (value >= 50) return const Color(0xFFFFC371);
    return const Color(0xFFFF5252);
  }
}
