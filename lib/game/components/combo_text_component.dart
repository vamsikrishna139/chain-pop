import 'package:flame/components.dart';
import 'package:flutter/material.dart';

/// Floating "×N" combo readout spawned at an extraction when the streak is
/// hot (≥ 3). Rises and fades over [_life], then removes itself — the visual
/// twin of the existing pop-pitch audio ramp.
class ComboTextComponent extends PositionComponent {
  static const double _life = 0.7;

  final double _riseSpeed;
  double _t = 0;
  late final TextPainter _painter;

  ComboTextComponent({
    required Vector2 cellCenter,
    required int streak,
    required Color color,
    required double cellSize,
  })  : _riseSpeed = cellSize * 1.1,
        super(position: cellCenter, anchor: Anchor.center) {
    _painter = TextPainter(
      text: TextSpan(
        text: '×$streak',
        style: TextStyle(
          color: color,
          fontSize: (cellSize * 0.42).clamp(12.0, 24.0),
          fontWeight: FontWeight.w800,
          shadows: const [Shadow(color: Colors.black54, blurRadius: 4)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  @override
  void update(double dt) {
    _t += dt;
    if (_t >= _life) {
      removeFromParent();
      return;
    }
    position.y -= _riseSpeed * dt;
  }

  @override
  void render(Canvas canvas) {
    final fade = (1.0 - _t / _life).clamp(0.0, 1.0);
    final rect = Rect.fromLTWH(
      -_painter.width / 2 - 4,
      -_painter.height / 2 - 4,
      _painter.width + 8,
      _painter.height + 8,
    );
    canvas.saveLayer(
        rect, Paint()..color = Colors.white.withValues(alpha: fade));
    _painter.paint(
      canvas,
      Offset(-_painter.width / 2, -_painter.height / 2),
    );
    canvas.restore();
  }
}
