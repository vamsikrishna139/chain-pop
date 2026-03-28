import 'dart:math';
import 'dart:ui';

import 'difficulty_mode.dart';

/// Named silhouettes used for irregular boards (subset of the bounding grid).
enum LayoutMaskKind {
  /// Full rectangle — caller should use `null` [LevelData.playCells], not this set.
  fullRect,

  /// ∨ opening upward, tip at bottom centre (wider toward the bottom row).
  vShape,

  /// Roughly house-plate / convex pentagon in pixel space, rasterised to cells.
  pentagon,

  /// Border with a rectangular bite removed (C / notch).
  cShape,
}

/// Builds the set of playable cell keys `"x,y"` for [kind] on a `w`×`h` grid.
///
/// When [kind] is [LayoutMaskKind.fullRect], returns `null` (meaning “no mask”).
Set<String>? buildLayoutMask(
  LayoutMaskKind kind,
  int w,
  int h, {
  Random? random,
}) {
  switch (kind) {
    case LayoutMaskKind.fullRect:
      return null;
    case LayoutMaskKind.vShape:
      return _vShape(w, h, random);
    case LayoutMaskKind.pentagon:
      return _pentagonCells(w, h, random);
    case LayoutMaskKind.cShape:
      return _cShape(w, h, random);
  }
}

/// Irregular layouts on medium vs hard (easy stays rectangular).
bool rollIrregularLayout(DifficultyMode mode, Random random) {
  switch (mode) {
    case DifficultyMode.easy:
      return false;
    case DifficultyMode.medium:
      return random.nextDouble() < 0.22;
    case DifficultyMode.hard:
      return random.nextDouble() < 0.58;
  }
}

LayoutMaskKind pickIrregularKind(Random random) {
  final r = random.nextDouble();
  if (r < 0.34) return LayoutMaskKind.vShape;
  if (r < 0.67) return LayoutMaskKind.pentagon;
  return LayoutMaskKind.cShape;
}

Set<String> _vShape(int w, int h, Random? random) {
  final cells = <String>{};
  var cx = w ~/ 2;
  if (random != null && w > 4 && random.nextBool()) {
    cx = cx + (random.nextBool() ? 1 : -1);
    cx = cx.clamp(1, w - 2);
  }
  final mirror = random?.nextBool() ?? false;
  for (var y = 0; y < h; y++) {
    final distFromBottom = h - 1 - y;
    final halfWidth = min(distFromBottom, max(w ~/ 2, 1));
    for (var dx = -halfWidth; dx <= halfWidth; dx++) {
      var x = cx + dx;
      if (mirror) x = w - 1 - x;
      if (x >= 0 && x < w) cells.add('$x,$y');
    }
  }
  return cells;
}

Set<String> _pentagonCells(int w, int h, Random? random) {
  final path = Path();
  final jitter = (random?.nextDouble() ?? 0.5) * 0.08;
  final x0 = w * (0.08 + jitter);
  final x1 = w * (0.92 - jitter);
  final yTop = h * (0.18 + jitter * 0.5);
  final yMid = h * (0.42);
  final yBot = h * (0.92 - jitter * 0.5);
  path.moveTo(w * 0.5, yTop);
  path.lineTo(x1, yMid);
  path.lineTo(w * 0.78, yBot);
  path.lineTo(w * 0.22, yBot);
  path.lineTo(x0, yMid);
  path.close();

  final cells = <String>{};
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (path.contains(Offset(x + 0.5, y + 0.5))) {
        cells.add('$x,$y');
      }
    }
  }
  if (cells.length < 9) {
    return _vShape(w, h, random);
  }
  return cells;
}

/// Thick frame with a rectangular void; a single-cell-wide passage links void to one edge.
Set<String> _cShape(int w, int h, Random? random) {
  final cells = <String>{};
  final iw = max(2, w ~/ 3);
  final ih = max(2, h ~/ 3);
  final ox = (w - iw) ~/ 2;
  final oy = (h - ih) ~/ 2;
  final openSide = random?.nextInt(4) ?? 0;
  final verticalSlit = openSide < 2;
  final slitX = ox + iw ~/ 2;
  final slitY = oy + ih ~/ 2;

  bool playableSlit(int x, int y) {
    if (verticalSlit) {
      if (x != slitX) return false;
      return openSide == 0 ? y <= oy + ih - 1 : y >= oy;
    }
    if (y != slitY) return false;
    return openSide == 2 ? x <= ox + iw - 1 : x >= ox;
  }

  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final inVoid = x >= ox && x < ox + iw && y >= oy && y < oy + ih;
      if (inVoid && !playableSlit(x, y)) continue;
      cells.add('$x,$y');
    }
  }
  return cells;
}
