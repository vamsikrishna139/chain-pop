import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
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

    final visitedSegments = <String>{};

    if (game.activeNodes.isEmpty) return;

    final stroke = (cellSize * 0.06).clamp(1.0, 4.0);
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: AppColors.guideLineAlpha)
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    void drawSegment(int cx, int cy, int nextX, int nextY) {
      final key = '$cx,$cy->$nextX,$nextY';
      final revKey = '$nextX,$nextY->$cx,$cy';
      if (visitedSegments.contains(key) || visitedSegments.contains(revKey)) return;
      visitedSegments.add(key);

      final p1 = Offset((cx + 0.5) * cellSize, (cy + 0.5) * cellSize);
      final p2 = Offset((nextX + 0.5) * cellSize, (nextY + 0.5) * cellSize);
      canvas.drawLine(p1, p2, paint);
    }

    void trace(NodeData node, Direction dir) {
      var cx = node.x;
      var cy = node.y;
      var hops = 0;
      while (hops < 50) {
        var nextX = cx;
        var nextY = cy;
        switch (dir) {
          case Direction.up: nextY--; break;
          case Direction.down: nextY++; break;
          case Direction.left: nextX--; break;
          case Direction.right: nextX++; break;
        }

        if (nextX < 0 || nextX >= gridWidth || nextY < 0 || nextY >= gridHeight) {
          final edgeX = nextX < 0 ? -0.5 : (nextX >= gridWidth ? gridWidth - 0.5 : cx + 0.5);
          final edgeY = nextY < 0 ? -0.5 : (nextY >= gridHeight ? gridHeight - 0.5 : cy + 0.5);
          canvas.drawLine(
            Offset((cx + 0.5) * cellSize, (cy + 0.5) * cellSize),
            Offset(edgeX * cellSize, edgeY * cellSize),
            paint,
          );
          break;
        }

        drawSegment(cx, cy, nextX, nextY);
        cx = nextX;
        cy = nextY;

        if (game.levelData.portalPairs.isNotEmpty) {
          for (final p in game.levelData.portalPairs) {
            if (p.x1 == cx && p.y1 == cy) {
              cx = p.x2; cy = p.y2; break;
            } else if (p.x2 == cx && p.y2 == cy) {
              cx = p.x1; cy = p.y1; break;
            }
          }
        }
        hops++;
      }
    }

    for (final n in game.activeNodes) {
      // Trace forward
      trace(n, n.dir);
      // Trace backward
      final opposite = n.dir == Direction.left ? Direction.right :
                       n.dir == Direction.right ? Direction.left :
                       n.dir == Direction.up ? Direction.down : Direction.up;
      trace(n, opposite);
    }
  }
}
