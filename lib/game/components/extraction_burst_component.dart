import 'package:flame/components.dart';
import 'package:flutter/material.dart';

/// One-shot expanding ring at the cell a node just vacated.
///
/// Board-local, self-removing after [_life]. Reuses the ring-ripple language
/// from the hint highlight so extraction feedback reads as the same family.
class ExtractionBurstComponent extends PositionComponent {
  final Color color;
  final double maxRadius;

  static const double _life = 0.35;

  double _t = 0;
  final Paint _ringPaint = Paint()..style = PaintingStyle.stroke;

  ExtractionBurstComponent({
    required Vector2 cellCenter,
    required this.color,
    required this.maxRadius,
  }) : super(position: cellCenter, anchor: Anchor.center);

  @override
  void update(double dt) {
    _t += dt;
    if (_t >= _life) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final progress = (_t / _life).clamp(0.0, 1.0);
    final eased = Curves.easeOut.transform(progress);
    _ringPaint
      ..color = color.withValues(alpha: (1.0 - progress) * 0.5)
      ..strokeWidth = 2.5 * (1.0 - progress * 0.6);
    canvas.drawCircle(
      Offset.zero,
      maxRadius * (0.35 + 0.65 * eased),
      _ringPaint,
    );
  }
}
