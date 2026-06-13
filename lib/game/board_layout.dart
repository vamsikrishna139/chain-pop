import 'dart:math' as math;
import 'package:chain_pop/game/levels/level.dart';
import 'board_layout.dart';

/// Bounding box representation of occupied cells on a grid.
class OccupiedBounds {
  final int minX;
  final int maxX;
  final int minY;
  final int maxY;
  final int bboxWidth;
  final int bboxHeight;

  const OccupiedBounds({
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
    required this.bboxWidth,
    required this.bboxHeight,
  });

  /// Derives bounds from [level.nodes], with safety padding `pad` (default 1).
  /// If the level has no nodes, falls back to the full grid bounds.
  factory OccupiedBounds.fromLevel(LevelData level, {int pad = 1}) {
    if (level.nodes.isEmpty) {
      return OccupiedBounds(
        minX: 0,
        maxX: math.max(0, level.gridWidth - 1),
        minY: 0,
        maxY: math.max(0, level.gridHeight - 1),
        bboxWidth: level.gridWidth,
        bboxHeight: level.gridHeight,
      );
    }

    var rawMinX = level.nodes.first.x;
    var rawMaxX = level.nodes.first.x;
    var rawMinY = level.nodes.first.y;
    var rawMaxY = level.nodes.first.y;

    for (final node in level.nodes) {
      if (node.x < rawMinX) rawMinX = node.x;
      if (node.x > rawMaxX) rawMaxX = node.x;
      if (node.y < rawMinY) rawMinY = node.y;
      if (node.y > rawMaxY) rawMaxY = node.y;
    }

    final frameMinX = (rawMinX - pad).clamp(0, math.max(0, level.gridWidth - 1)).toInt();
    final frameMaxX = (rawMaxX + pad).clamp(0, math.max(0, level.gridWidth - 1)).toInt();
    final frameMinY = (rawMinY - pad).clamp(0, math.max(0, level.gridHeight - 1)).toInt();
    final frameMaxY = (rawMaxY + pad).clamp(0, math.max(0, level.gridHeight - 1)).toInt();

    return OccupiedBounds(
      minX: frameMinX,
      maxX: frameMaxX,
      minY: frameMinY,
      maxY: frameMaxY,
      bboxWidth: (frameMaxX - frameMinX + 1).toInt(),
      bboxHeight: (frameMaxY - frameMinY + 1).toInt(),
    );
  }
}

/// Pure layout math for fitting the logical grid into the Flame viewport with
/// HUD reserves and an inner gutter (shadows / hint rings).
///
/// [fitCellSize] must never **inflate** the cell above the band fit; a minimum
/// size is applied only when the full grid still fits at that size (unlike
/// `.clamp(min, max)` on the fit alone, which can overflow the band).
class BoardLayoutMetrics {
  BoardLayoutMetrics({
    required this.cellSize,
    required this.gridPixelW,
    required this.gridPixelH,
    required this.offsetX,
    required this.offsetY,
    required this.usableW,
    required this.usableH,
  });

  final double cellSize;
  final double gridPixelW;
  final double gridPixelH;
  final double offsetX;
  final double offsetY;
  final double usableW;
  final double usableH;

  /// Largest cell edge length such that the full grid fits in [bandW]×[bandH],
  /// capped by [maxCell]. [minPreferredCell] is applied only if the grid still
  /// fits at that size on both axes (never forces overflow).
  static double fitCellSize({
    required double bandW,
    required double bandH,
    required int gridWidth,
    required int gridHeight,
    double maxCell = 96.0,
    double minPreferredCell = 26.0,
  }) {
    if (gridWidth <= 0 || gridHeight <= 0) return 0;
    if (bandW <= 0 || bandH <= 0) return 0;
    final cellW = bandW / gridWidth;
    final cellH = bandH / gridHeight;
    var s = math.min(cellW, cellH);
    s = math.min(s, maxCell);
    final atMinFits = minPreferredCell * gridWidth <= bandW &&
        minPreferredCell * gridHeight <= bandH;
    if (atMinFits) {
      s = math.max(s, minPreferredCell);
      s = math.min(s, maxCell);
    }
    return s;
  }

  /// Calculates the largest cell size that fits a bounding box size in the playfield target fill area.
  static double fitCellSizeForBounds({
    required double bandW,
    required double bandH,
    required int bboxWidth,
    required int bboxHeight,
    required double targetFill,
    double maxCell = 96.0,
    double minPreferredCell = 26.0,
  }) {
    if (bboxWidth <= 0 || bboxHeight <= 0) return 0;
    if (bandW <= 0 || bandH <= 0) return 0;

    final targetW = bandW * targetFill;
    final targetH = bandH * targetFill;

    final cellW = targetW / bboxWidth;
    final cellH = targetH / bboxHeight;
    var s = math.min(cellW, cellH);
    s = math.min(s, maxCell);

    final atMinFits = minPreferredCell * bboxWidth <= targetW &&
        minPreferredCell * bboxHeight <= targetH;
    if (atMinFits) {
      s = math.max(s, minPreferredCell);
      s = math.min(s, maxCell);
    }
    return s;
  }

  /// [fitCellSizeForBounds] zooms into the occupied bbox, which on sparse
  /// boards (e.g. a single node in a 4×4 tutorial grid) inflates the cell until
  /// the *full* rendered grid spills past the band edges. This caps the result
  /// so `cell × gridWidth ≤ bandW` and `cell × gridHeight ≤ bandH` — the whole
  /// grid always fits at base zoom; the player can still pinch-zoom afterward.
  static double fitCellSizeForBoundsCappedToGrid({
    required double bandW,
    required double bandH,
    required int bboxWidth,
    required int bboxHeight,
    required int gridWidth,
    required int gridHeight,
    required double targetFill,
    double maxCell = 96.0,
    double minPreferredCell = 26.0,
  }) {
    final fit = fitCellSizeForBounds(
      bandW: bandW,
      bandH: bandH,
      bboxWidth: bboxWidth,
      bboxHeight: bboxHeight,
      targetFill: targetFill,
      maxCell: maxCell,
      minPreferredCell: minPreferredCell,
    );
    if (gridWidth <= 0 || gridHeight <= 0) return fit;
    final gridCap = math.min(bandW / gridWidth, bandH / gridHeight);
    if (gridCap <= 0) return fit;
    return math.min(fit, gridCap);
  }

  /// [topReserved] / [bottomReserved] are distances from screen edges to the
  /// playfield band (same convention as [ChainPopGame]).
  static BoardLayoutMetrics compute({
    required double screenW,
    required double screenH,
    required double topReserved,
    required double bottomReserved,
    required int gridWidth,
    required int gridHeight,
    double outerMargin = 24.0,
    double innerGutter = 8.0,
    double minPreferredCell = 26.0,
    double cellMax = 96.0,
  }) {
    final usableW = math.max(0.0, screenW - outerMargin * 2);
    final usableH = math.max(0.0, screenH - topReserved - bottomReserved - outerMargin);

    final layoutW = (usableW - innerGutter * 2).clamp(0.0, double.infinity);
    final layoutH = (usableH - innerGutter * 2).clamp(0.0, double.infinity);

    final cellSize = fitCellSize(
      bandW: layoutW,
      bandH: layoutH,
      gridWidth: gridWidth,
      gridHeight: gridHeight,
      maxCell: cellMax,
      minPreferredCell: minPreferredCell,
    );

    final gridPixelW = cellSize * gridWidth;
    final gridPixelH = cellSize * gridHeight;

    final offsetX = (screenW - gridPixelW) / 2;
    final offsetY = topReserved + (usableH - gridPixelH) / 2;

    return BoardLayoutMetrics(
      cellSize: cellSize,
      gridPixelW: gridPixelW,
      gridPixelH: gridPixelH,
      offsetX: offsetX,
      offsetY: offsetY,
      usableW: usableW,
      usableH: usableH,
    );
  }
}
