import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import 'package:haptic_feedback/haptic_feedback.dart';
import 'dart:math' as math;
import '../levels/level.dart';
import '../chain_pop_game.dart';

class NodeComponent extends PositionComponent
    with TapCallbacks, HasGameRef<ChainPopGame> {
  final NodeData data;
  final double cellSize;

  bool isPopping = false;
  bool isJamming = false;
  bool isHighlighted = false;

  Vector2 _originalPos = Vector2.zero();
  double _shakeTimer = 0.0;
  double _highlightTimer = 0.0; // replaces Future.delayed — lifecycle-safe

  static const double _shakeDuration = 0.3;
  static const double _highlightDuration = 1.5;
  static const double _speed = 1500.0;

  NodeComponent({required this.data, required this.cellSize})
      : super(
          size: Vector2.all(cellSize * 0.82),
          anchor: Anchor.center,
        );

  @override
  Future<void> onLoad() async {
    _updatePositionFromGrid();
  }

  void _updatePositionFromGrid() {
    position = Vector2((data.x + 0.5) * cellSize, (data.y + 0.5) * cellSize);
    _originalPos = position.clone();
  }

  void highlight() {
    isHighlighted = true;
    _highlightTimer = 0.0;
  }

  @override
  void render(Canvas canvas) {
    // During fly-out the node is no longer in _extractableIds — still draw it
    // at full brightness so the motion to the screen edge is visible.
    final isExtractable = isPopping || gameRef.isExtractable(data.id);
    final rect = size.toRect();
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(cellSize * 0.18));

    // ── Visual state: extractable = full glow; blocked = dimmed ──────────────
    final nodeColor = isHighlighted ? Colors.white : data.color;
    final opacity = isExtractable ? 1.0 : 0.55;
    final effectiveColor = nodeColor.withOpacity(opacity);

    // Outer glow — stronger for extractable nodes, subtle for blocked
    final glowRadius =
        isHighlighted ? 20.0 : (isExtractable ? 14.0 : 4.0);
    final glowColor = (isHighlighted ? Colors.white : data.color)
        .withOpacity(isExtractable ? 0.55 : 0.18);

    canvas.drawShadow(
      Path()..addRRect(rrect),
      glowColor,
      glowRadius,
      true,
    );

    // Fill
    canvas.drawRRect(
      rrect,
      Paint()..color = effectiveColor,
    );

    // Inner gloss
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.white.withOpacity(isExtractable ? 0.35 : 0.12),
            Colors.transparent,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(rect),
    );

    // Extractable border pulse (slight white rim)
    if (isExtractable && !isHighlighted) {
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = Colors.white.withOpacity(0.18)
          ..style = PaintingStyle.stroke
          ..strokeWidth = cellSize * 0.045,
      );
    }

    // Arrow
    final arrowPaint = Paint()
      ..color = isHighlighted
          ? Colors.black
          : Colors.white.withOpacity(isExtractable ? 0.92 : 0.45)
      ..strokeWidth = cellSize * 0.09
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final center = rect.center;
    final al = cellSize * 0.22;

    final arrow = Path();
    switch (data.dir) {
      case Direction.up:
        arrow
          ..moveTo(center.dx, center.dy + al)
          ..lineTo(center.dx, center.dy - al)
          ..moveTo(center.dx - al / 2, center.dy - al / 4)
          ..lineTo(center.dx, center.dy - al)
          ..lineTo(center.dx + al / 2, center.dy - al / 4);
      case Direction.down:
        arrow
          ..moveTo(center.dx, center.dy - al)
          ..lineTo(center.dx, center.dy + al)
          ..moveTo(center.dx - al / 2, center.dy + al / 4)
          ..lineTo(center.dx, center.dy + al)
          ..lineTo(center.dx + al / 2, center.dy + al / 4);
      case Direction.left:
        arrow
          ..moveTo(center.dx + al, center.dy)
          ..lineTo(center.dx - al, center.dy)
          ..moveTo(center.dx - al / 4, center.dy - al / 2)
          ..lineTo(center.dx - al, center.dy)
          ..lineTo(center.dx - al / 4, center.dy + al / 2);
      case Direction.right:
        arrow
          ..moveTo(center.dx - al, center.dy)
          ..lineTo(center.dx + al, center.dy)
          ..moveTo(center.dx + al / 4, center.dy - al / 2)
          ..lineTo(center.dx + al, center.dy)
          ..lineTo(center.dx + al / 4, center.dy + al / 2);
    }
    canvas.drawPath(arrow, arrowPaint);
  }

  @override
  void update(double dt) {
    // ── Highlight timeout (replaces Future.delayed — no memory leak) ─────────
    if (isHighlighted) {
      _highlightTimer += dt;
      if (_highlightTimer >= _highlightDuration) {
        isHighlighted = false;
        _highlightTimer = 0.0;
      }
    }

    // ── Pop (fly off in arrow direction) ────────────────────────────────────
    if (isPopping) {
      position += _directionVector() * _speed * dt;
      // [position] is board-local; compare in game/world space so we actually
      // reach the viewport edge before removing.
      final world = absoluteCenter;
      final gs = gameRef.size;
      final pad = math.max(size.x, size.y) * 0.55 + 48;
      if (world.x < -pad ||
          world.x > gs.x + pad ||
          world.y < -pad ||
          world.y > gs.y + pad) {
        removeFromParent();
        gameRef.checkWinCondition();
      }
      return;
    }

    // ── Jam shake ────────────────────────────────────────────────────────────
    if (isJamming) {
      _shakeTimer += dt;
      if (_shakeTimer >= _shakeDuration) {
        isJamming = false;
        position = _originalPos.clone();
        _shakeTimer = 0.0;
      } else {
        final shakeAmount = (1.0 - (_shakeTimer / _shakeDuration)) * 10.0;
        final offset = math.sin(_shakeTimer * 60) * shakeAmount;
        position = _originalPos + _directionVector() * offset;
      }
    }
  }

  @override
  void onTapDown(TapDownEvent event) {
    if (isPopping || isJamming) return;

    if (gameRef.canExtract(data)) {
      isPopping = true;
      gameRef.registerExtraction(data);
      Haptics.vibrate(HapticsType.medium);
    } else {
      isJamming = true;
      _shakeTimer = 0.0;
      Haptics.vibrate(HapticsType.heavy);
      gameRef.reportJam();
    }
  }

  Vector2 _directionVector() {
    switch (data.dir) {
      case Direction.up:    return Vector2(0, -1);
      case Direction.down:  return Vector2(0, 1);
      case Direction.left:  return Vector2(-1, 0);
      case Direction.right: return Vector2(1, 0);
    }
  }
}
