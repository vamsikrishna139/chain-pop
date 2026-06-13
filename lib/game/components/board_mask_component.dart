import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import '../../theme/world_theme.dart';
import '../levels/level.dart';

/// Renders the playfield silhouette so irregular [LevelData.playCells] shapes
/// (rings, corridors, archipelagos) read clearly against the background.
///
/// Playable cells are drawn as subtle accent-tinted tiles with a soft glow
/// along the silhouette boundary; non-playable cells show the background.
/// Rectangular boards (null [LevelData.playCells]) get the same tile grid so
/// every level sits on a visible "chassis" instead of floating in a void.
///
/// The whole layer is static for a given layout, so it is recorded once into a
/// [ui.Picture] and replayed each frame — zero per-frame iteration cost.
class BoardMaskComponent extends PositionComponent {
  final LevelData levelData;
  final double cellSize;
  final WorldTheme theme;

  ui.Picture? _picture;

  BoardMaskComponent({
    required this.levelData,
    required this.cellSize,
    WorldTheme? theme,
  })  : theme = theme ?? WorldTheme.forLevel(levelData.levelId),
        super(
          size: Vector2(
            levelData.gridWidth * cellSize,
            levelData.gridHeight * cellSize,
          ),
        );

  bool _isPlayable(int x, int y) {
    final play = levelData.playCells;
    if (play == null || play.isEmpty) return true;
    return play.contains('$x,$y');
  }

  ui.Picture _buildPicture() {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final inset = cellSize * 0.06;
    final radius = Radius.circular(cellSize * 0.16);

    // Soft accent glow hugging the silhouette boundary, drawn under the tiles.
    // Only true boundary edges (playable cell against non-playable space) are
    // stroked, so the glow traces the shape without hazing the interior.
    final outline = Path();
    for (var y = 0; y < levelData.gridHeight; y++) {
      for (var x = 0; x < levelData.gridWidth; x++) {
        if (!_isPlayable(x, y)) continue;
        final l = x * cellSize;
        final t = y * cellSize;
        final r = l + cellSize;
        final b = t + cellSize;
        if (y == 0 || !_isPlayable(x, y - 1)) {
          outline
            ..moveTo(l, t)
            ..lineTo(r, t);
        }
        if (y == levelData.gridHeight - 1 || !_isPlayable(x, y + 1)) {
          outline
            ..moveTo(l, b)
            ..lineTo(r, b);
        }
        if (x == 0 || !_isPlayable(x - 1, y)) {
          outline
            ..moveTo(l, t)
            ..lineTo(l, b);
        }
        if (x == levelData.gridWidth - 1 || !_isPlayable(x + 1, y)) {
          outline
            ..moveTo(r, t)
            ..lineTo(r, b);
        }
      }
    }
    final glowPaint = Paint()
      ..color = theme.silhouetteGlow
      ..style = PaintingStyle.stroke
      ..strokeWidth = cellSize * 0.10
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, cellSize * 0.18);
    canvas.drawPath(outline, glowPaint);

    final fillPaint = Paint()..color = theme.tileFill;
    final borderPaint = Paint()
      ..color = theme.tileBorder
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    for (var y = 0; y < levelData.gridHeight; y++) {
      for (var x = 0; x < levelData.gridWidth; x++) {
        if (!_isPlayable(x, y)) continue;
        final tile = RRect.fromRectAndRadius(
          Rect.fromLTWH(
            x * cellSize + inset,
            y * cellSize + inset,
            cellSize - inset * 2,
            cellSize - inset * 2,
          ),
          radius,
        );
        canvas.drawRRect(tile, fillPaint);
        canvas.drawRRect(tile, borderPaint);
      }
    }

    return recorder.endRecording();
  }

  @override
  void render(Canvas canvas) {
    canvas.drawPicture(_picture ??= _buildPicture());
  }
}
