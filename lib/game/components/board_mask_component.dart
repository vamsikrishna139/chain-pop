import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../levels/level.dart';

/// Fills non-playable cells so irregular [LevelData.playCells] silhouettes read
/// clearly against the game background.
class BoardMaskComponent extends PositionComponent {
  final LevelData levelData;
  final double cellSize;

  BoardMaskComponent({
    required this.levelData,
    required this.cellSize,
  }) : super(
          size: Vector2(
            levelData.gridWidth * cellSize,
            levelData.gridHeight * cellSize,
          ),
        );

  @override
  void render(Canvas canvas) {
    final play = levelData.playCells;
    if (play == null || play.isEmpty) return;

    final paint = Paint()..color = AppColors.surface;
    for (var y = 0; y < levelData.gridHeight; y++) {
      for (var x = 0; x < levelData.gridWidth; x++) {
        if (!play.contains('$x,$y')) {
          canvas.drawRect(
            Rect.fromLTWH(x * cellSize, y * cellSize, cellSize, cellSize),
            paint,
          );
        }
      }
    }
  }
}
