import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../../game/levels/generation/difficulty_mode.dart';
import '../../../models/difficulty.dart';
import 'timer_pause_chip.dart';

class GamePauseOverlay extends StatelessWidget {
  final DifficultyMode difficulty;
  final int? timeLeftSec;
  final int? timeLimitSec;
  final Duration elapsed;
  final VoidCallback onMenuFromPause;
  final VoidCallback onTogglePause;
  final VoidCallback onRestartFromPause;

  const GamePauseOverlay({
    super.key,
    required this.difficulty,
    required this.timeLeftSec,
    required this.timeLimitSec,
    required this.elapsed,
    required this.onMenuFromPause,
    required this.onTogglePause,
    required this.onRestartFromPause,
  });

  @override
  Widget build(BuildContext context) {
    final accent = difficulty.color;

    return Positioned.fill(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                color: Colors.black.withOpacity(0.38),
              ),
            ),
          ),
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (_) {},
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: onMenuFromPause,
                          borderRadius: BorderRadius.circular(12),
                          child: const Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(
                              Icons.chevron_left_rounded,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                        ),
                      ),
                      const Spacer(),
                      TimerPauseChip(
                        timeLeftSec: timeLeftSec,
                        timeLimitSec: timeLimitSec,
                        elapsed: elapsed,
                        color: accent,
                        onTap: onTogglePause,
                        emphasizeResume: true,
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    'PAUSED',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.95),
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap the timer to resume',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: accent.withOpacity(0.85),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton.icon(
                          onPressed: onRestartFromPause,
                          icon: Icon(
                            Icons.refresh_rounded,
                            size: 20,
                            color: accent.withOpacity(0.9),
                          ),
                          label: Text(
                            'RESTART',
                            style: TextStyle(
                              color: accent.withOpacity(0.95),
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                        const SizedBox(width: 20),
                        TextButton.icon(
                          onPressed: onMenuFromPause,
                          icon: const Icon(
                            Icons.home_rounded,
                            size: 20,
                            color: Colors.white54,
                          ),
                          label: const Text(
                            'MENU',
                            style: TextStyle(
                              color: Colors.white54,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 48),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
