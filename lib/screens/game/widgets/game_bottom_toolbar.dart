import 'package:flutter/material.dart';

import 'game_toolbar_button.dart';
import 'undo_restart_button.dart';

class GameBottomToolbar extends StatelessWidget {
  /// Placed on the inner [Padding] for bottom inset measurement.
  final Key? measureKey;
  final Color accent;
  final bool axisGuidesVisible;
  final bool canUndo;
  final VoidCallback onHint;
  final VoidCallback onToggleGuides;
  final VoidCallback onResetView;
  final VoidCallback onUndo;
  final VoidCallback onRestart;

  const GameBottomToolbar({
    super.key,
    this.measureKey,
    required this.accent,
    required this.axisGuidesVisible,
    required this.canUndo,
    required this.onHint,
    required this.onToggleGuides,
    required this.onResetView,
    required this.onUndo,
    required this.onRestart,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          key: measureKey,
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GameToolbarButton(
                icon: Icons.lightbulb_outline_rounded,
                accent: accent,
                tooltip: 'Hint',
                onPressed: onHint,
              ),
              const SizedBox(width: 12),
              GameToolbarButton(
                icon: Icons.grid_on_rounded,
                accent: accent,
                tooltip: axisGuidesVisible ? 'Hide guides' : 'Show guides',
                selected: axisGuidesVisible,
                onPressed: onToggleGuides,
              ),
              const SizedBox(width: 12),
              GameToolbarButton(
                icon: Icons.zoom_out_map_rounded,
                accent: accent,
                tooltip: 'Reset view',
                onPressed: onResetView,
              ),
              const SizedBox(width: 12),
              UndoRestartButton(
                accent: accent,
                canUndo: canUndo,
                onUndo: onUndo,
                onRestart: onRestart,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
