import 'package:flutter/material.dart';

/// Compact session-goal indicator: "🎯 Win 3 levels · 1/3". Sits under the
/// header so the player has a mid-session objective beyond the current level.
class SessionGoalChip extends StatelessWidget {
  final String label;
  final int progress;
  final int target;
  final bool complete;
  final Color accent;

  const SessionGoalChip({
    super.key,
    required this.label,
    required this.progress,
    required this.target,
    required this.complete,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final tint = complete ? const Color(0xFF00FF87) : accent;
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: tint.withValues(alpha: 0.5)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                complete ? Icons.check_circle_rounded : Icons.flag_rounded,
                size: 13,
                color: tint.withValues(alpha: 0.95),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
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
              const SizedBox(width: 6),
              Text(
                complete ? 'DONE' : '$progress/$target',
                style: TextStyle(
                  color: tint,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
