import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';

class _TimerBadge extends StatefulWidget {
  final int timeLeftSec;
  final int timeLimitSec;
  final Color color;

  const _TimerBadge({
    required this.timeLeftSec,
    required this.timeLimitSec,
    required this.color,
  });

  @override
  State<_TimerBadge> createState() => _TimerBadgeState();
}

class _TimerBadgeState extends State<_TimerBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    final frac = widget.timeLimitSec > 0
        ? widget.timeLeftSec / widget.timeLimitSec
        : 0.0;
    if (frac < 0.22) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant _TimerBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    final frac = widget.timeLimitSec > 0
        ? widget.timeLeftSec / widget.timeLimitSec
        : 0.0;
    final urgent = frac < 0.22;
    if (urgent && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!urgent && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frac = widget.timeLimitSec > 0
        ? widget.timeLeftSec / widget.timeLimitSec
        : 0.0;
    final urgent = frac < 0.22;
    final c = frac < 0.20
        ? AppColors.timerWarning
        : frac < 0.40
            ? AppColors.timerCaution
            : widget.color;
    final m = (widget.timeLeftSec ~/ 60).toString();
    final s = (widget.timeLeftSec % 60).toString().padLeft(2, '0');

    final iconRow = Row(
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

    return Semantics(
      label:
          'Time remaining $m minutes $s seconds${urgent ? ', running low' : ''}',
      child: urgent
          ? AnimatedBuilder(
              animation: _pulse,
              builder: (_, __) => Transform.scale(
                scale: 1 + _pulse.value * 0.06,
                child: iconRow,
              ),
            )
          : iconRow,
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
            child: Semantics(
              button: true,
              label: hasCountdown
                  ? 'Timer, tap to pause or resume'
                  : 'Elapsed time clock, tap to pause or resume',
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
                          color: color.withValues(alpha: 0.9),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _fmtElapsed(elapsed),
                          style: TextStyle(
                            color: color.withValues(alpha: 0.95),
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
                      color: Colors.white.withValues(
                        alpha: emphasizeResume ? 0.75 : 0.42,
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
      ),
    );
  }
}
