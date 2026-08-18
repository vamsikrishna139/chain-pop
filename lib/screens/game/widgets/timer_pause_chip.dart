import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../theme/app_colors.dart';

class TimerPauseChip extends StatefulWidget {
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

  @override
  State<TimerPauseChip> createState() => _TimerPauseChipState();
}

class _TimerPauseChipState extends State<TimerPauseChip> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    final frac = widget.timeLimitSec != null && widget.timeLimitSec! > 0
        ? (widget.timeLeftSec ?? 0) / widget.timeLimitSec!
        : 1.0;
    if (frac < 0.22 && widget.timeLimitSec != null) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant TimerPauseChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    final frac = widget.timeLimitSec != null && widget.timeLimitSec! > 0
        ? (widget.timeLeftSec ?? 0) / widget.timeLimitSec!
        : 1.0;
    final urgent = frac < 0.22 && widget.timeLimitSec != null;
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

  static String _fmtElapsed(Duration d) {
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  static String _fmtSeconds(int secs) {
    final m = (secs ~/ 60).toString();
    final s = (secs % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final hasCountdown = widget.timeLimitSec != null && widget.timeLeftSec != null;
    final frac = hasCountdown && widget.timeLimitSec! > 0
        ? widget.timeLeftSec! / widget.timeLimitSec!
        : 1.0;
    final urgent = frac < 0.22 && hasCountdown;

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final scale = urgent ? 1.0 + _pulse.value * 0.05 : 1.0;
        final bgColor = urgent ? Colors.redAccent.withValues(alpha: 0.1) : AppColors.surface;
        final borderColor = urgent ? Colors.redAccent.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.1);
        final iconColor = urgent ? Colors.redAccent : Colors.white70;
        final textColor = urgent ? Colors.redAccent : Colors.white;

        return Transform.scale(
          scale: scale,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: borderColor),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.schedule_rounded, size: 14, color: iconColor),
                  const SizedBox(width: 6),
                  Text(
                    hasCountdown ? _fmtSeconds(widget.timeLeftSec!) : _fmtElapsed(widget.elapsed),
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    width: 1,
                    height: 12,
                    color: Colors.white24,
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    widget.emphasizeResume ? Icons.play_arrow_rounded : Icons.pause_rounded,
                    size: 14,
                    color: Colors.white54,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
