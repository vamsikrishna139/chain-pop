import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';

class _TimerBadge extends StatelessWidget {
  final int timeLeftSec;
  final int timeLimitSec;
  final Color color;

  const _TimerBadge({
    required this.timeLeftSec,
    required this.timeLimitSec,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final frac = timeLimitSec > 0 ? timeLeftSec / timeLimitSec : 0.0;
    final c = frac < 0.20
        ? AppColors.timerWarning
        : frac < 0.40
            ? AppColors.timerCaution
            : color;
    final m = (timeLeftSec ~/ 60).toString();
    final s = (timeLeftSec % 60).toString().padLeft(2, '0');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.timer_outlined, size: 14, color: c),
        const SizedBox(width: 4),
        Text(
          '$m:$s',
          style: TextStyle(
            color: c,
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }
}

/// Tappable timer (timed modes) or elapsed clock (Easy) — tap pauses / resumes.
class TimerPauseChip extends StatelessWidget {
  final int? timeLeftSec;
  final int? timeLimitSec;
  final Duration elapsed;
  final Color color;
  final VoidCallback onTap;
  final bool emphasizeResume;

  const TimerPauseChip({
    super.key,
    required this.timeLeftSec,
    required this.timeLimitSec,
    required this.elapsed,
    required this.color,
    required this.onTap,
    this.emphasizeResume = false,
  });

  static String _fmtElapsed(Duration d) {
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final hasCountdown = timeLimitSec != null && timeLeftSec != null;
    final hint = emphasizeResume ? 'TAP TO RESUME' : 'TAP TO PAUSE';
    final tooltip = emphasizeResume
        ? 'Resume game'
        : (hasCountdown ? 'Pause — tap the timer' : 'Pause — tap the clock');

    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (hasCountdown)
                  _TimerBadge(
                    timeLeftSec: timeLeftSec!,
                    timeLimitSec: timeLimitSec!,
                    color: color,
                  )
                else
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.schedule_rounded,
                        size: 14,
                        color: color.withOpacity(0.9),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _fmtElapsed(elapsed),
                        style: TextStyle(
                          color: color.withOpacity(0.95),
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 3),
                Text(
                  hint,
                  style: TextStyle(
                    color: Colors.white.withOpacity(
                      emphasizeResume ? 0.75 : 0.42,
                    ),
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.9,
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
