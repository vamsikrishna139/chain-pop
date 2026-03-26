import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import 'package:haptic_feedback/haptic_feedback.dart';
import 'dart:math' as math;
import '../levels/level.dart';
import '../chain_pop_game.dart';

class NodeComponent extends PositionComponent with TapCallbacks, HasGameRef<ChainPopGame> {
  final NodeData data;
  final double cellSize;
  
  bool isPopping = false;
  bool isJamming = false;
  bool isHighlighted = false;

  Vector2 _originalPos = Vector2.zero();
  double _shakeTimer = 0.0;
  static const double _shakeDuration = 0.3;
  static const double _speed = 1500.0;

  NodeComponent({
    required this.data,
    required this.cellSize,
  }) : super(
         size: Vector2.all(cellSize * 0.82),
         anchor: Anchor.center,
       );

  @override
  Future<void> onLoad() async {
    _updatePositionFromGrid();
  }

  void _updatePositionFromGrid() {
    position = Vector2(
      (data.x + 0.5) * cellSize,
      (data.y + 0.5) * cellSize,
    );
    _originalPos = position.clone();
  }

  void highlight() {
    isHighlighted = true;
    Future.delayed(const Duration(milliseconds: 1500), () {
      isHighlighted = false;
    });
  }

  @override
  void render(Canvas canvas) {
    final rect = size.toRect();
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(cellSize * 0.18));
    
    // Modern Box Style
    final paint = Paint()
      ..color = isHighlighted ? Colors.white : data.color
      ..style = PaintingStyle.fill;
      
    // Outer Glow / Shadow
    canvas.drawShadow(
      Path()..addRRect(rrect),
      (isHighlighted ? Colors.white : data.color).withOpacity(0.5),
      isHighlighted ? 20.0 : 12.0,
      true,
    );

    canvas.drawRRect(rrect, paint);

    // Inner bevel/gloss
    final glossPaint = Paint()
      ..shader = LinearGradient(
        colors: [Colors.white.withOpacity(0.4), Colors.transparent],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(rect);
    canvas.drawRRect(rrect, glossPaint);

    // Draw Arrow
    final arrowPaint = Paint()
      ..color = isHighlighted ? Colors.black : Colors.white
      ..strokeWidth = cellSize * 0.09
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final center = rect.center;
    final arrowLength = cellSize * 0.22;
    
    Path arrowPath = Path();
    
    switch (data.dir) {
      case Direction.up:
        arrowPath.moveTo(center.dx, center.dy + arrowLength);
        arrowPath.lineTo(center.dx, center.dy - arrowLength);
        arrowPath.moveTo(center.dx - arrowLength/2, center.dy - arrowLength/4);
        arrowPath.lineTo(center.dx, center.dy - arrowLength);
        arrowPath.lineTo(center.dx + arrowLength/2, center.dy - arrowLength/4);
        break;
      case Direction.down:
        arrowPath.moveTo(center.dx, center.dy - arrowLength);
        arrowPath.lineTo(center.dx, center.dy + arrowLength);
        arrowPath.moveTo(center.dx - arrowLength/2, center.dy + arrowLength/4);
        arrowPath.lineTo(center.dx, center.dy + arrowLength);
        arrowPath.lineTo(center.dx + arrowLength/2, center.dy + arrowLength/4);
        break;
      case Direction.left:
        arrowPath.moveTo(center.dx + arrowLength, center.dy);
        arrowPath.lineTo(center.dx - arrowLength, center.dy);
        arrowPath.moveTo(center.dx - arrowLength/4, center.dy - arrowLength/2);
        arrowPath.lineTo(center.dx - arrowLength, center.dy);
        arrowPath.lineTo(center.dx - arrowLength/4, center.dy + arrowLength/2);
        break;
      case Direction.right:
        arrowPath.moveTo(center.dx - arrowLength, center.dy);
        arrowPath.lineTo(center.dx + arrowLength, center.dy);
        arrowPath.moveTo(center.dx + arrowLength/4, center.dy - arrowLength/2);
        arrowPath.lineTo(center.dx + arrowLength, center.dy);
        arrowPath.lineTo(center.dx + arrowLength/4, center.dy + arrowLength/2);
        break;
    }
    
    canvas.drawPath(arrowPath, arrowPaint);
  }

  @override
  void update(double dt) {
    if (isPopping) {
      final dirVec = _getDirectionVector();
      position += dirVec * _speed * dt;
      
      if (position.x < -200 || position.x > gameRef.size.x + 200 ||
          position.y < -200 || position.y > gameRef.size.y + 200) {
        removeFromParent();
        gameRef.checkWinCondition();
      }
    } else if (isJamming) {
      _shakeTimer += dt;
      if (_shakeTimer >= _shakeDuration) {
        isJamming = false;
        position = _originalPos.clone();
        _shakeTimer = 0.0;
      } else {
        final shakeAmount = (1.0 - (_shakeTimer / _shakeDuration)) * 10.0;
        final dirVec = _getDirectionVector();
        final offset = math.sin(_shakeTimer * 60) * shakeAmount;
        position = _originalPos + (dirVec * offset);
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
      gameRef.reportJam(); // ← notify screen for star tracking
    }
  }

  Vector2 _getDirectionVector() {
    switch (data.dir) {
      case Direction.up: return Vector2(0, -1);
      case Direction.down: return Vector2(0, 1);
      case Direction.left: return Vector2(-1, 0);
      case Direction.right: return Vector2(1, 0);
    }
  }
}
