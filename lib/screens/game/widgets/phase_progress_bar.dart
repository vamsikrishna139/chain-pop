import 'package:flutter/material.dart';

/// Segmented clearance bar with flow → crunch → release coloring.
class PhaseProgressBar extends StatelessWidget {
  final int removedNodes;
  final int totalNodes;

  const PhaseProgressBar({
    super.key,
    required this.removedNodes,
    required this.totalNodes,
  });

  static const _flowGreen = Color(0xFF00FF87);
  static const _crunchAmber = Color(0xFFFFC371);
  static const _releaseBright = Color(0xFF60EFFF);

  static Color _segmentColor(int segmentIndex, int total) {
    if (total <= 0) return _flowGreen;
    final clearedFrac = (segmentIndex + 1) / total;
    if (clearedFrac <= 0.35) return _flowGreen;
    if (clearedFrac <= 0.65) return _crunchAmber;
    return _releaseBright;
  }

  @override
  Widget build(BuildContext context) {
    if (totalNodes <= 0) {
      return const SizedBox(width: 120, height: 6);
    }

    return Semantics(
      label: '$removedNodes of $totalNodes nodes cleared',
      child: SizedBox(
        width: 120,
        height: 6,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: Row(
            children: [
              for (var i = 0; i < totalNodes; i++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: i < totalNodes - 1 ? 1 : 0),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: i < removedNodes
                            ? _segmentColor(i, totalNodes)
                            : Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
