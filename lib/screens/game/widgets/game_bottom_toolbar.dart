import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'ad_badge.dart';
import 'undo_restart_button.dart';
import '../../../theme/app_colors.dart';

class GameBottomToolbar extends StatelessWidget {
  final Key? measureKey;
  final Color accent;
  final bool showHintAdBadge;
  final bool showUndoAdBadge;
  final bool axisGuidesVisible;
  final bool canUndo;
  final VoidCallback onHint;
  final VoidCallback onToggleGuides;
  final VoidCallback? onZoomIn;
  final VoidCallback onResetView;
  final VoidCallback onUndo;
  final VoidCallback onRestart;

  const GameBottomToolbar({
    super.key,
    this.measureKey,
    required this.accent,
    this.showHintAdBadge = false,
    this.showUndoAdBadge = false,
    required this.axisGuidesVisible,
    required this.canUndo,
    required this.onHint,
    required this.onToggleGuides,
    this.onZoomIn,
    required this.onResetView,
    required this.onUndo,
    required this.onRestart,
    this.hasBanner = false,
  });

  /// Whether a banner ad (or the space reserved for one) sits directly below.
  /// The toolbar then needs only a hairline of bottom padding — the ad is the
  /// footer's bottom edge. Without one (premium, offline) it keeps its full
  /// padding above the gesture bar.
  final bool hasBanner;

  @override
  Widget build(BuildContext context) {
    // No bottom inset here: the toolbar sits above the banner ad, and the
    // game screen applies the system inset once, under the whole footer.
    // Insetting here left a dead strip between the toolbar and the ad.
    return SafeArea(
      bottom: false,
      child: Padding(
        key: measureKey,
        padding: EdgeInsets.fromLTRB(16, 0, 16, hasBanner ? 4 : 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Left Controls: Undo/Restart and Hint
            Expanded(
              child: Row(
                children: [
                  UndoRestartButton(
                    accent: accent,
                    canUndo: canUndo,
                    showAdBadge: showUndoAdBadge,
                    onUndo: onUndo,
                    onRestart: onRestart,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: InkWell(
                      onTap: onHint,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.1)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.lightbulb_outline_rounded,
                                size: 16, color: Colors.amberAccent),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'HINT',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.amberAccent,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (showHintAdBadge) ...[
                              const SizedBox(width: 6),
                              const AdBadge(color: Colors.amberAccent),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Right Controls: Grid, Zoom
            Row(
              children: [
                _buildSmallBtn(
                  label: 'Toggle Grid',
                  icon: Icons.grid_on_rounded,
                  active: axisGuidesVisible,
                  onTap: onToggleGuides,
                ),
                if (onZoomIn != null) ...[
                  const SizedBox(width: 8),
                  _buildSmallBtn(
                    label: 'Zoom In',
                    icon: Icons.zoom_in_rounded,
                    active: false,
                    onTap: onZoomIn!,
                  ),
                ],
                const SizedBox(width: 8),
                _buildSmallBtn(
                  label: 'Zoom Out',
                  icon: Icons.zoom_out_map_rounded,
                  active: false,
                  onTap: onResetView,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSmallBtn(
      {required String label,
      required IconData icon,
      required bool active,
      required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: active ? accent.withValues(alpha: 0.2) : AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: active ? accent : Colors.white.withValues(alpha: 0.1)),
        ),
        child: Icon(
          icon,
          size: 18,
          color: active ? accent : Colors.white70,
        ),
      ),
    );
  }
}
