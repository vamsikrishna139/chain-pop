import 'dart:math' as math;

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
