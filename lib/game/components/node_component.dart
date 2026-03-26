import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import 'package:haptic_feedback/haptic_feedback.dart';
import '../levels/level.dart';
import '../chain_pop_game.dart';

class NodeComponent extends PositionComponent with TapCallbacks, HasGameRef<ChainPopGame> {
  final NodeData data;
  final double cellSize;
  
  // Animation states
  bool isMoving = false;
  bool isPopping = false;
  bool isJamming = false;
  
  Vector2 _originalPos = Vector2.zero();
  double _shakeTimer = 0.0;
  static const double _shakeDuration = 0.3;
  static const double _speed = 500.0; // pixels per second

  NodeComponent({
    required this.data,
    required this.cellSize,
  }) : super(
         size: Vector2.all(cellSize * 0.9), // Add some padding
         anchor: Anchor.center,
       );

  @override
  Future<void> onLoad() async {
    // Set position based on grid coordinates
    _updatePositionFromGrid();
  }

  void _updatePositionFromGrid() {
    position = Vector2(
      (data.x + 0.5) * cellSize,
      (data.y + 0.5) * cellSize,
    );
    _originalPos = position.clone();
  }

  @override
  void render(Canvas canvas) {
    if (isPopping) return; // Don't render while logically popped out

    // Beautiful styling
    final rect = size.toRect();
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(cellSize * 0.2));
    
    // Gradient based on direction
    final paint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF4FACFE), Color(0xFF00F2FE)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(rect)
      ..style = PaintingStyle.fill;
      
    // Shadow
    canvas.drawShadow(
      Path()..addRRect(rrect),
      Colors.black.withOpacity(0.5),
      8.0,
      true,
    );

    canvas.drawRRect(rrect, paint);

    // Draw Arrow
    final arrowPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final center = rect.center;
    final arrowLength = cellSize * 0.25;
    
    Path arrowPath = Path();
    
    switch (data.dir) {
      case Direction.up:
        arrowPath.moveTo(center.dx, center.dy + arrowLength);
        arrowPath.lineTo(center.dx, center.dy - arrowLength);
        arrowPath.moveTo(center.dx - arrowLength/2, center.dy - arrowLength/2);
        arrowPath.lineTo(center.dx, center.dy - arrowLength);
        arrowPath.lineTo(center.dx + arrowLength/2, center.dy - arrowLength/2);
        break;
      case Direction.down:
        arrowPath.moveTo(center.dx, center.dy - arrowLength);
        arrowPath.lineTo(center.dx, center.dy + arrowLength);
        arrowPath.moveTo(center.dx - arrowLength/2, center.dy + arrowLength/2);
        arrowPath.lineTo(center.dx, center.dy + arrowLength);
        arrowPath.lineTo(center.dx + arrowLength/2, center.dy + arrowLength/2);
        break;
      case Direction.left:
        arrowPath.moveTo(center.dx + arrowLength, center.dy);
        arrowPath.lineTo(center.dx - arrowLength, center.dy);
        arrowPath.moveTo(center.dx - arrowLength/2, center.dy - arrowLength/2);
        arrowPath.lineTo(center.dx - arrowLength, center.dy);
        arrowPath.lineTo(center.dx - arrowLength/2, center.dy + arrowLength/2);
        break;
      case Direction.right:
        arrowPath.moveTo(center.dx - arrowLength, center.dy);
        arrowPath.lineTo(center.dx + arrowLength, center.dy);
        arrowPath.moveTo(center.dx + arrowLength/2, center.dy - arrowLength/2);
        arrowPath.lineTo(center.dx + arrowLength, center.dy);
        arrowPath.lineTo(center.dx + arrowLength/2, center.dy + arrowLength/2);
        break;
    }
    
    canvas.drawPath(arrowPath, arrowPaint);
  }

  @override
  void update(double dt) {
    if (isPopping) {
      // Fly out of screen
      final dirVec = _getDirectionVector();
      position += dirVec * _speed * dt;
      
      // Check if completely offscreen
      if (!gameRef.camera.visibleWorldRect.contains(position.toOffset())) {
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
        // Shake logic
        final shakeAmount = (1.0 - (_shakeTimer / _shakeDuration)) * 10.0;
        final dirVec = _getDirectionVector();
        
        // Rapid oscillation
        final offset = (_shakeTimer * 50).sin() * shakeAmount;
        position = _originalPos + (dirVec * offset);
      }
    }
  }

  @override
  void onTapDown(TapDownEvent event) {
    if (isMoving || isPopping || isJamming) return;
    
    // Check if path is free
    if (gameRef.canExtract(data)) {
      // Extract
      isPopping = true;
      gameRef.registerExtraction(data);
      Haptics.vibrate(HapticsType.light);
    } else {
      // Jam
      isJamming = true;
      _shakeTimer = 0.0;
      Haptics.vibrate(HapticsType.heavy);
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
