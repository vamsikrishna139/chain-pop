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
/// Portal cells ([LevelData.portalPairs]) are drawn here too, as a ring with
/// the pair's number at both ends. The number, not just the colour, is what
/// pairs them, so the cue survives colourblind play. A portal used to be
/// invisible until a ray happened to cross it (audit P1-6c).
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

    _drawTray(canvas, outline);
    _drawVoidMarkers(canvas);

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

    _drawPortals(canvas);

    return recorder.endRecording();
  }

  /// Paints one continuous rounded body under all playable cells.
  ///
  /// The tray is the playable region dilated by a small pad with rounded
  /// convex corners: each playable cell is filled, then the boundary edges
  /// ([outline]) are stroked with round caps/joins at twice the pad. Concave
  /// corners fill in and convex ones round off, so the mask reads as one
  /// deliberate shape. Painting the same dilation slightly larger in the rim
  /// colour first leaves a crisp edge line around it. All of it is static and
  /// lands in the cached picture.
  void _drawTray(Canvas canvas, Path outline) {
    final pad = cellSize * 0.10;
    final rimWidth = (cellSize * 0.035).clamp(1.0, 2.5);

    final cells = Path();
    for (var y = 0; y < levelData.gridHeight; y++) {
      for (var x = 0; x < levelData.gridWidth; x++) {
        if (!_isPlayable(x, y)) continue;
        cells.addRect(
          Rect.fromLTWH(x * cellSize, y * cellSize, cellSize, cellSize),
        );
      }
    }

    void dilate(Color color, double grow) {
      canvas
        ..drawPath(cells, Paint()..color = color)
        ..drawPath(
          outline,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = grow * 2
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
    }

    dilate(theme.trayRim, pad + rimWidth);
    dilate(theme.trayFill, pad);
  }

  /// Faint "+" at the centre of every void cell inside the grid frame. A cross
  /// rather than a dot so it never reads as one of the ambient background
  /// particles.
  ///
  /// Rays walk the full rectangle and pass straight through voids, so hinting
  /// the grid there is truthful, and it turns holes and bays into visibly
  /// "part of the board" space instead of dead screen. Cells covered by the
  /// tray's pad are skipped implicitly because the tray is painted first and
  /// the dots are tiny.
  void _drawVoidMarkers(Canvas canvas) {
    final play = levelData.playCells;
    if (play == null || play.isEmpty) return;
    final paint = Paint()
      ..color = theme.voidMarker
      ..strokeWidth = (cellSize * 0.025).clamp(1.0, 2.0)
      ..strokeCap = StrokeCap.round;
    final arm = cellSize * 0.06;
    for (var y = 0; y < levelData.gridHeight; y++) {
      for (var x = 0; x < levelData.gridWidth; x++) {
        if (_isPlayable(x, y)) continue;
        final c = Offset((x + 0.5) * cellSize, (y + 0.5) * cellSize);
        canvas
          ..drawLine(c - Offset(arm, 0), c + Offset(arm, 0), paint)
          ..drawLine(c - Offset(0, arm), c + Offset(0, arm), paint);
      }
    }
  }

  /// One hue per pair; the number carries the pairing on its own.
  static const List<Color> _portalColors = [
    Color(0xFFB388FF),
    Color(0xFF4DD0E1),
    Color(0xFFFFB74D),
  ];

  void _drawPortals(Canvas canvas) {
    final pairs = levelData.portalPairs;
    for (var i = 0; i < pairs.length; i++) {
      final color = _portalColors[i % _portalColors.length];
      final p = pairs[i];
      for (final (x, y) in [(p.x1, p.y1), (p.x2, p.y2)]) {
        final c = Offset((x + 0.5) * cellSize, (y + 0.5) * cellSize);
        canvas
          ..drawCircle(
            c,
            cellSize * 0.34,
            Paint()
              ..color = color.withValues(alpha: 0.30)
              ..maskFilter = MaskFilter.blur(BlurStyle.normal, cellSize * 0.10),
          )
          ..drawCircle(
            c,
            cellSize * 0.30,
            Paint()
              ..color = color
              ..style = PaintingStyle.stroke
              ..strokeWidth = cellSize * 0.07,
          );
        final label = TextPainter(
          text: TextSpan(
            text: '${i + 1}',
            style: TextStyle(
              color: color,
              fontSize: cellSize * 0.32,
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        label.paint(canvas, c - Offset(label.width / 2, label.height / 2));
      }
    }
  }

  @override
  void render(Canvas canvas) {
    canvas.drawPicture(_picture ??= _buildPicture());
  }
}
