import 'package:flutter/material.dart';

import 'game_toolbar_button.dart';
import 'undo_restart_button.dart';

class GameBottomToolbar extends StatelessWidget {
  /// Placed on the inner [Padding] for bottom inset measurement.
  final Key? measureKey;
  final Color accent;

  /// Hard campaign + daily challenge: hints go through rewarded flow — show a small badge on the hint control.
  final bool showHintAdBadge;
  final bool axisGuidesVisible;
  final bool canUndo;
  final VoidCallback onHint;
  final VoidCallback onToggleGuides;

  /// Tutorial: explicit zoom-in control (pinch still works in all modes).
  final VoidCallback? onZoomIn;
  final VoidCallback onResetView;
  final VoidCallback onUndo;
  final VoidCallback onRestart;

  const GameBottomToolbar({
    super.key,
    this.measureKey,
    required this.accent,
    this.showHintAdBadge = false,
    required this.axisGuidesVisible,
    required this.canUndo,
    required this.onHint,
    required this.onToggleGuides,
    this.onZoomIn,
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              final row = Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    button: true,
                    label: showHintAdBadge
                        ? 'Hint. Extra hints use a short video ad.'
                        : 'Hint',
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          ExcludeSemantics(
                            child: GameToolbarButton(
                              icon: Icons.lightbulb_outline_rounded,
                              accent: accent,
                              tooltip: 'Hint',
                              onPressed: onHint,
                            ),
                          ),
                          if (showHintAdBadge)
                            Positioned(
                              top: -4,
                              right: -4,
                              child: ExcludeSemantics(
                                child: IgnorePointer(
                                  child: Container(
                                    width: 23,
                                    height: 23,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: accent,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black
                                              .withValues(alpha: 0.28),
                                          blurRadius: 3,
                                          offset: const Offset(0, 1),
                                        ),
                                      ],
                                    ),
                                    child: const Text(
                                      'Ad',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w800,
                                        height: 1,
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Semantics(
                    button: true,
                    label: axisGuidesVisible
                        ? 'Hide alignment lines'
                        : 'Show alignment lines',
                    child: ExcludeSemantics(
                      child: GameToolbarButton(
                        icon: Icons.grid_on_rounded,
                        accent: accent,
                        tooltip: axisGuidesVisible
                            ? 'Hide alignment lines'
                            : 'Align lines',
                        selected: axisGuidesVisible,
                        onPressed: onToggleGuides,
                      ),
                    ),
                  ),
                  if (onZoomIn != null) ...[
                    const SizedBox(width: 12),
                    Semantics(
                      button: true,
                      label: 'Zoom in',
                      child: ExcludeSemantics(
                        child: GameToolbarButton(
                          icon: Icons.zoom_in_rounded,
                          accent: accent,
                          tooltip: 'Zoom in',
                          onPressed: onZoomIn!,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 12),
                  Semantics(
                    button: true,
                    label: 'Reset zoom',
                    child: ExcludeSemantics(
                      child: GameToolbarButton(
                        icon: Icons.zoom_out_map_rounded,
                        accent: accent,
                        tooltip: 'Reset zoom',
                        onPressed: onResetView,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Semantics(
                    button: true,
                    label:
                        'Undo last move. Press and hold to restart the level.',
                    child: ExcludeSemantics(
                      child: UndoRestartButton(
                        accent: accent,
                        canUndo: canUndo,
                        onUndo: onUndo,
                        onRestart: onRestart,
                      ),
                    ),
                  ),
                ],
              );

              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: row,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
