import 'package:flame/components.dart';
import 'package:flutter/material.dart';

/// One-shot horizontal sweep across the row a relay just rotated. Makes the
/// relay's row-rotation read as a deliberate event instead of an instant snap.
/// Board-local (added to the board), self-removing after [_duration].
class RelaySweepComponent extends PositionComponent {
  final int gridWidth;
  final double cellSize;
  final Color color;

  double _t = 0;
  static const double _duration = 0.36;

  RelaySweepComponent({
    required int rowY,
    required this.gridWidth,
    required this.cellSize,
    required this.color,
  }) : super(
          position: Vector2(0, rowY * cellSize),
          size: Vector2(gridWidth * cellSize, cellSize),
        );

  late final Rect _rowRect = size.toRect().deflate(cellSize * 0.06);
  late final RRect _rowRRect =
      RRect.fromRectAndRadius(_rowRect, Radius.circular(cellSize * 0.2));

  @override
  void update(double dt) {
    _t += dt;
    if (_t >= _duration) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final p = (_t / _duration).clamp(0.0, 1.0);

    // Row glow that fades out — tints the whole rotated row.
    final glow = (1.0 - p) * 0.26;
    if (glow > 0.004) {
      canvas.drawRRect(
        _rowRRect,
        Paint()..color = color.withValues(alpha: glow),
      );
    }

    // Bright blurred bar travelling left→right across the row.
    final sweepX = p * (size.x + cellSize) - cellSize * 0.5;
    final bar = Rect.fromLTWH(sweepX, 0, cellSize * 0.9, size.y);
    canvas.drawRect(
      bar,
      Paint()
        ..color = color.withValues(alpha: (1.0 - p) * 0.5)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, cellSize * 0.35),
    );
  }
}
