import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../chain_pop_game.dart';
import '../levels/level.dart';
import '../levels/level_solver.dart';

/// Dotted ray preview from a long-pressed node to the grid edge or first blocker.
class RayPreviewComponent extends PositionComponent
    with HasGameReference<ChainPopGame> {
  final NodeData source;
  final RayTraceResult trace;
  final double cellSize;

  /// 0..1 opacity multiplier. Touch-down aim shows a faint ray (~0.4); a long
  /// press shows the full ray (1.0).
  final double intensity;

  RayPreviewComponent({
    required this.source,
    required this.trace,
    required this.cellSize,
    required int gridWidth,
    required int gridHeight,
    this.intensity = 1.0,
  }) : super(
          size: Vector2(gridWidth * cellSize, gridHeight * cellSize),
          anchor: Anchor.topLeft,
          position: Vector2.zero(),
        );

  static const Color _rayColor = Color(0xCCFFC371);
  static const Color _blockerTint = Color(0x66FFC371);

  @override
  void render(Canvas canvas) {
    final gw = game.levelData.gridWidth;
    final gh = game.levelData.gridHeight;
    var cx = source.x;
    var cy = source.y;
    var hops = 0;
    
    // Draw segments until we reach the trace end or a blocker
    while (hops < 50) {
      var nextX = cx;
      var nextY = cy;
      switch (source.dir) {
        case Direction.up: nextY--; break;
        case Direction.down: nextY++; break;
        case Direction.left: nextX--; break;
        case Direction.right: nextX++; break;
      }
      
      if (nextX < 0 || nextX >= gw || nextY < 0 || nextY >= gh) {
        _drawDottedRay(
          canvas, 
          Offset((cx + 0.5) * cellSize, (cy + 0.5) * cellSize),
          _edgeOffset(cx, cy, source.dir, gw, gh)
        );
        break;
      }
      
      // Stop exactly at the trace end (which is the blocker or last cell)
      if (nextX == trace.endX && nextY == trace.endY) {
        _drawDottedRay(
          canvas, 
          Offset((cx + 0.5) * cellSize, (cy + 0.5) * cellSize),
          Offset((nextX + 0.5) * cellSize, (nextY + 0.5) * cellSize)
        );
        break;
      }
      
      _drawDottedRay(
        canvas, 
        Offset((cx + 0.5) * cellSize, (cy + 0.5) * cellSize),
        Offset((nextX + 0.5) * cellSize, (nextY + 0.5) * cellSize)
      );
      
      cx = nextX;
      cy = nextY;
      
      bool warped = false;
      for (final p in game.levelData.portalPairs) {
        if (p.x1 == cx && p.y1 == cy) {
          cx = p.x2; cy = p.y2; warped = true; break;
        } else if (p.x2 == cx && p.y2 == cy) {
          cx = p.x1; cy = p.y1; warped = true; break;
        }
      }
      if (warped && cx == trace.endX && cy == trace.endY) {
         break;
      }
      hops++;
    }

    if (trace.hitsBlocker) {
      final end = Offset((trace.endX + 0.5) * cellSize, (trace.endY + 0.5) * cellSize);
      final half = cellSize * 0.41;
      final rect = Rect.fromCenter(
        center: end,
        width: half * 2,
        height: half * 2,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(cellSize * 0.16)),
        Paint()..color = _blockerTint.withValues(alpha: 0.4 * intensity),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(cellSize * 0.16)),
        Paint()
          ..color = AppColors.accentMedium.withValues(alpha: 0.85 * intensity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = (cellSize * 0.05).clamp(1.5, 3.5),
      );
    }
  }

  Offset _edgeOffset(int cx, int cy, Direction dir, int gw, int gh) {
    if (dir == Direction.left) {
      return Offset(0, (cy + 0.5) * cellSize);
    }
    if (dir == Direction.right) {
      return Offset(gw * cellSize, (cy + 0.5) * cellSize);
    }
    if (dir == Direction.up) {
      return Offset((cx + 0.5) * cellSize, 0);
    }
    if (dir == Direction.down) {
      return Offset((cx + 0.5) * cellSize, gh * cellSize);
    }
    return Offset.zero;
  }

  void _drawDottedRay(Canvas canvas, Offset start, Offset end) {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final length = math.sqrt(dx * dx + dy * dy);
    if (length < 1) return;

    const dash = 7.0;
    const gap = 5.0;
    final unitX = dx / length;
    final unitY = dy / length;

    final paint = Paint()
      ..color = _rayColor.withValues(alpha: 0.8 * intensity)
      ..strokeWidth = (cellSize * 0.045).clamp(1.5, 3.0)
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    var traveled = 0.0;
    var drawing = true;
    while (traveled < length) {
      final seg = drawing ? dash : gap;
      final next = math.min(traveled + seg, length);
      if (drawing) {
        canvas.drawLine(
          Offset(start.dx + unitX * traveled, start.dy + unitY * traveled),
          Offset(start.dx + unitX * next, start.dy + unitY * next),
          paint,
        );
      }
      traveled = next;
      drawing = !drawing;
    }
  }
}
