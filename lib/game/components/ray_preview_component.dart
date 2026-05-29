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

  RayPreviewComponent({
    required this.source,
    required this.trace,
    required this.cellSize,
    required int gridWidth,
    required int gridHeight,
  }) : super(
          size: Vector2(gridWidth * cellSize, gridHeight * cellSize),
          anchor: Anchor.topLeft,
          position: Vector2.zero(),
        );

  static const Color _rayColor = Color(0xCCFFC371);
  static const Color _blockerTint = Color(0x66FFC371);

  @override
  void render(Canvas canvas) {
    final start = Offset(
      (source.x + 0.5) * cellSize,
      (source.y + 0.5) * cellSize,
    );
    final end = _endCenter();

    _drawDottedRay(canvas, start, end);

    if (trace.hitsBlocker) {
      final half = cellSize * 0.41;
      final rect = Rect.fromCenter(
        center: end,
        width: half * 2,
        height: half * 2,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(cellSize * 0.16)),
        Paint()..color = _blockerTint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(cellSize * 0.16)),
        Paint()
          ..color = AppColors.accentMedium.withValues(alpha: 0.85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = (cellSize * 0.05).clamp(1.5, 3.5),
      );
    }
  }

  Offset _endCenter() {
    final gw = game.levelData.gridWidth;
    final gh = game.levelData.gridHeight;
    var x = trace.endX;
    var y = trace.endY;

    if (x < 0) {
      return Offset(0, (source.y + 0.5) * cellSize);
    }
    if (x >= gw) {
      return Offset(gw * cellSize, (source.y + 0.5) * cellSize);
    }
    if (y < 0) {
      return Offset((source.x + 0.5) * cellSize, 0);
    }
    if (y >= gh) {
      return Offset((source.x + 0.5) * cellSize, gh * cellSize);
    }

    return Offset((x + 0.5) * cellSize, (y + 0.5) * cellSize);
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
      ..color = _rayColor
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
