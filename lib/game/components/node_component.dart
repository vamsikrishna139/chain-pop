import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import 'package:haptic_feedback/haptic_feedback.dart';
import 'dart:math' as math;
import '../levels/level.dart';
import '../chain_pop_game.dart';
import '../../services/game_sfx.dart';

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

  late Rect _rect;
  late RRect _rrect;
  late Path _shadowPath;
  late Path _arrowPath;
  late Paint _fillPaint;
  late Paint _gradientPaint;
  late Paint _arrowPaintNormal;

  Color _shadowGlowColor = Colors.transparent;
  double _shadowGlowRadius = 14.0;

  static const double _shakeDuration = 0.3;
  static const double _highlightDuration = 2.0;
  static const double _highlightPulseCount = 3.0;
  static const double _speed = 1500.0;

  final Paint _ringPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.5;

  NodeComponent({required this.data, required this.cellSize})
      : super(
          size: Vector2.all(cellSize * 0.82),
          anchor: Anchor.center,
        );

  @override
  Future<void> onLoad() async {
    _updatePositionFromGrid();
    _buildRenderCaches();
  }

  void _buildRenderCaches() {
    _rect = size.toRect();
    _rrect = RRect.fromRectAndRadius(
      _rect,
      Radius.circular(cellSize * 0.18),
    );
    _shadowPath = Path()..addRRect(_rrect);

    _gradientPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.white.withOpacity(0.35),
          Colors.transparent,
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(_rect);

    _fillPaint = Paint()..color = data.color.withOpacity(1.0);

    final strokeW = cellSize * 0.09;
    _arrowPaintNormal = Paint()
      ..color = Colors.white.withOpacity(0.92)
      ..strokeWidth = strokeW
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    _buildArrowPath();

    _shadowGlowColor = data.color.withOpacity(0.55);
    _shadowGlowRadius = 14.0;
  }

  void _buildArrowPath() {
    final arrow = Path();
    final center = _rect.center;
    final al = cellSize * 0.22;
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
    _arrowPath = arrow;
  }

  void _updatePositionFromGrid() {
    position = Vector2((data.x + 0.5) * cellSize, (data.y + 0.5) * cellSize);
    _originalPos = position.clone();
  }

  void highlight() {
    isHighlighted = true;
    _highlightTimer = 0.0;
  }

  void _syncColorsFromSettings() {
    final c = gameRef.effectiveNodeColor(data);
    _fillPaint.color = c.withOpacity(1.0);
    _shadowGlowColor = c.withOpacity(0.55);
  }

  @override
  void render(Canvas canvas) {
    _syncColorsFromSettings();
    if (isHighlighted) {
      _renderHighlighted(canvas);
    } else {
      canvas.drawShadow(
          _shadowPath, _shadowGlowColor, _shadowGlowRadius, true);
      canvas.drawRRect(_rrect, _fillPaint);
      canvas.drawRRect(_rrect, _gradientPaint);
      canvas.drawPath(_arrowPath, _arrowPaintNormal);
    }
  }

  /// Pulsing scale + expanding ring ripple — much more noticeable than a
  /// static color swap and universally reads as "tap me."
  void _renderHighlighted(Canvas canvas) {
    final progress = _highlightTimer / _highlightDuration;
    final fadeOut =
        progress < 0.7 ? 1.0 : ((1.0 - progress) / 0.3).clamp(0.0, 1.0);

    final phase =
        _highlightTimer * math.pi * _highlightPulseCount / _highlightDuration;
    final pulseVal = math.sin(phase).abs();
    final center = _rect.center;

    // ── Expanding ring ripple (one ring per pulse cycle) ──
    final ringPeriod = _highlightDuration / _highlightPulseCount;
    final ringT = (_highlightTimer % ringPeriod) / ringPeriod;
    final baseRadius = _rect.width * 0.5;
    final ringRadius = baseRadius + ringT * baseRadius * 0.6;
    final ringOpacity = (1.0 - ringT) * 0.45 * fadeOut;
    if (ringOpacity > 0.005) {
      _ringPaint
        ..color = gameRef.effectiveNodeColor(data).withOpacity(ringOpacity)
        ..strokeWidth = 2.5 * (1.0 - ringT * 0.6);
      canvas.drawCircle(center, ringRadius, _ringPaint);
    }

    // ── Pulsing scale + intensified glow ──
    final scaleAmt = 1.0 + 0.09 * pulseVal * fadeOut;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scaleAmt, scaleAmt);
    canvas.translate(-center.dx, -center.dy);

    final glowStrength = 14.0 + 12.0 * pulseVal * fadeOut;
    final glowOpacity = (0.55 + 0.3 * pulseVal * fadeOut).clamp(0.0, 1.0);
    canvas.drawShadow(
      _shadowPath,
      gameRef.effectiveNodeColor(data).withOpacity(glowOpacity),
      glowStrength,
      true,
    );
    canvas.drawRRect(_rrect, _fillPaint);
    canvas.drawRRect(_rrect, _gradientPaint);
    canvas.drawPath(_arrowPath, _arrowPaintNormal);

    canvas.restore();
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
    if (isPopping || isJamming || gameRef.hasWon || gameRef.isGameOver) return;

    if (gameRef.canExtract(data)) {
      isPopping = true;
      gameRef.registerExtraction(data);
      if (gameRef.hapticsEnabled) {
        Haptics.vibrate(HapticsType.medium);
      }
      gameRef.playSfx(
        GameSfx.pop,
        playbackRate: gameRef.popPlaybackRate,
      );
    } else {
      isJamming = true;
      _shakeTimer = 0.0;
      if (gameRef.hapticsEnabled) {
        Haptics.vibrate(HapticsType.heavy);
      }
      gameRef.playSfx(GameSfx.jam);
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
