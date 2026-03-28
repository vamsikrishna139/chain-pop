import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import '../chain_pop_game.dart';
import '../levels/level.dart';

/// Full-width / full-height axis lines for each active node's facing direction,
/// so collinear arrows read as sharing the same row or column.
///
/// Lives in board-local space (sibling of [NodeComponent]s), so it scales and
/// pans with the board under pinch zoom — no separate alignment step.
class ArrowAxisGuideComponent extends PositionComponent
    with HasGameReference<ChainPopGame> {
  final double cellSize;
  final int gridWidth;
  final int gridHeight;

  ArrowAxisGuideComponent({
    required this.cellSize,
    required this.gridWidth,
    required this.gridHeight,
  }) : super(
          size: Vector2(gridWidth * cellSize, gridHeight * cellSize),
          anchor: Anchor.topLeft,
          position: Vector2.zero(),
        );

  @override
  void render(Canvas canvas) {
    if (!game.axisGuidesVisible) return;

    final gw = gridWidth * cellSize;
    final gh = gridHeight * cellSize;

    final horizontalRows = <int>{};
    final verticalCols = <int>{};
    for (final n in game.activeNodes) {
      switch (n.dir) {
        case Direction.left:
        case Direction.right:
          horizontalRows.add(n.y);
          break;
        case Direction.up:
        case Direction.down:
          verticalCols.add(n.x);
          break;
      }
    }

    if (horizontalRows.isEmpty && verticalCols.isEmpty) return;

    final stroke = (cellSize * 0.06).clamp(1.0, 4.0);
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.14)
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (final row in horizontalRows) {
      final y = (row + 0.5) * cellSize;
      canvas.drawLine(Offset(0, y), Offset(gw, y), paint);
    }
    for (final col in verticalCols) {
      final x = (col + 0.5) * cellSize;
      canvas.drawLine(Offset(x, 0), Offset(x, gh), paint);
    }
  }
}
