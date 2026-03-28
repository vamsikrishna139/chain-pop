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

  /// Rhombus / Manhattan-distance circle.
  diamond,

  /// Horizontal + vertical bars intersecting at centre.
  cross,

  /// L-shaped region, randomly rotated.
  lShape,

  /// Full rectangle with a rectangular hole in the centre.
  donut,

  /// Sinusoidal band across the grid.
  zigzag,

  /// Organic blob with random radial variation.
  randomBlob,
}

/// Builds the set of playable cell keys `"x,y"` for [kind] on a `w`×`h` grid.
///
/// When [kind] is [LayoutMaskKind.fullRect], returns `null` (meaning "no mask").
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
    case LayoutMaskKind.diamond:
      return _diamond(w, h, random);
    case LayoutMaskKind.cross:
      return _cross(w, h, random);
    case LayoutMaskKind.lShape:
      return _lShapeCells(w, h, random);
    case LayoutMaskKind.donut:
      return _donut(w, h, random);
    case LayoutMaskKind.zigzag:
      return _zigzag(w, h, random);
    case LayoutMaskKind.randomBlob:
      return _randomBlob(w, h, random);
  }
}

/// Irregular layouts on each difficulty mode.
bool rollIrregularLayout(DifficultyMode mode, Random random) {
  switch (mode) {
    case DifficultyMode.easy:
      return random.nextDouble() < 0.12;
    case DifficultyMode.medium:
      return random.nextDouble() < 0.22;
    case DifficultyMode.hard:
      return random.nextDouble() < 0.58;
  }
}

/// Picks a random irregular mask kind.
/// When [preferred] is provided, picks only from that subset.
LayoutMaskKind pickIrregularKind(Random random,
    {List<LayoutMaskKind>? preferred}) {
  if (preferred != null && preferred.isNotEmpty) {
    return preferred[random.nextInt(preferred.length)];
  }
  const all = [
    LayoutMaskKind.vShape,
    LayoutMaskKind.pentagon,
    LayoutMaskKind.cShape,
    LayoutMaskKind.diamond,
    LayoutMaskKind.cross,
    LayoutMaskKind.lShape,
    LayoutMaskKind.donut,
    LayoutMaskKind.zigzag,
    LayoutMaskKind.randomBlob,
  ];
  return all[random.nextInt(all.length)];
}

// ═══════════════════════════════════════════════════════════════════════════
// Original shapes
// ═══════════════════════════════════════════════════════════════════════════

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

// ═══════════════════════════════════════════════════════════════════════════
// New shapes
// ═══════════════════════════════════════════════════════════════════════════

/// Rhombus — cells within Manhattan distance of the centre.
Set<String> _diamond(int w, int h, Random? random) {
  final cells = <String>{};
  final cx = w / 2.0;
  final cy = h / 2.0;
  final jitter = (random?.nextDouble() ?? 0.5) * 0.15;
  final radius = min(w, h) / 2.0 - 0.3 + jitter;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if ((x + 0.5 - cx).abs() + (y + 0.5 - cy).abs() <= radius) {
        cells.add('$x,$y');
      }
    }
  }
  if (cells.length < 6) return _vShape(w, h, random);
  return cells;
}

/// Plus / cross — two intersecting bars of ~35% grid width.
Set<String> _cross(int w, int h, Random? random) {
  final cells = <String>{};
  final armW = max(1, (w * 0.38).round());
  final armH = max(1, (h * 0.38).round());
  final cx = w ~/ 2;
  final cy = h ~/ 2;
  final halfW = armW ~/ 2;
  final halfH = armH ~/ 2;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if ((x - cx).abs() <= halfW || (y - cy).abs() <= halfH) {
        cells.add('$x,$y');
      }
    }
  }
  if (cells.length < 9) return _diamond(w, h, random);
  return cells;
}

/// L-shape — two perpendicular bars; rotated randomly among 4 orientations.
Set<String> _lShapeCells(int w, int h, Random? random) {
  final cells = <String>{};
  final barW = max(2, (w * 0.42).round());
  final barH = max(2, (h * 0.42).round());
  final rotation = random?.nextInt(4) ?? 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      bool include = false;
      switch (rotation) {
        case 0:
          include = y >= h - barH || x < barW;
        case 1:
          include = y >= h - barH || x >= w - barW;
        case 2:
          include = y < barH || x >= w - barW;
        case 3:
          include = y < barH || x < barW;
      }
      if (include) cells.add('$x,$y');
    }
  }
  if (cells.length < 9) return _diamond(w, h, random);
  return cells;
}

/// Donut — full rectangle with a rectangular hole in the centre.
Set<String> _donut(int w, int h, Random? random) {
  final cells = <String>{};
  final jitter = (random?.nextDouble() ?? 0.5) * 0.06;
  final holeW = max(1, (w * (0.32 + jitter)).round());
  final holeH = max(1, (h * (0.32 + jitter)).round());
  final ox = (w - holeW) ~/ 2;
  final oy = (h - holeH) ~/ 2;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final inHole = x >= ox && x < ox + holeW && y >= oy && y < oy + holeH;
      if (!inHole) cells.add('$x,$y');
    }
  }
  return cells;
}

/// Sinusoidal band — a wavy stripe across the grid.
Set<String> _zigzag(int w, int h, Random? random) {
  final cells = <String>{};
  final bandWidth = max(2, min(w, h) ~/ 3);
  final periods = 2 + (random?.nextInt(2) ?? 0);
  final vertical = random?.nextBool() ?? false;
  final span = vertical ? w : h;
  final length = vertical ? h : w;

  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final progress = (vertical ? y : x) / max(1, length);
      final perp = (vertical ? x : y).toDouble();
      final center =
          span / 2.0 + sin(progress * periods * pi) * span * 0.28;
      if ((perp - center).abs() < bandWidth) {
        cells.add('$x,$y');
      }
    }
  }
  if (cells.length < 9) return _diamond(w, h, random);
  return cells;
}

/// Organic blob — polar shape with randomly varying radii at 8 angles,
/// linearly interpolated for smooth edges.
Set<String> _randomBlob(int w, int h, Random? random) {
  final cells = <String>{};
  final rng = random ?? Random();
  final cx = w / 2.0;
  final cy = h / 2.0;
  final baseR = min(w, h) / 2.2;
  const nAngles = 8;
  final radii =
      List.generate(nAngles, (_) => baseR * (0.5 + rng.nextDouble() * 0.7));

  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final dx = x + 0.5 - cx;
      final dy = y + 0.5 - cy;
      final dist = sqrt(dx * dx + dy * dy);
      final angle = atan2(dy, dx) + pi; // 0 → 2π
      final sector = angle / (2 * pi) * nAngles;
      final i0 = sector.floor() % nAngles;
      final i1 = (i0 + 1) % nAngles;
      final frac = sector - sector.floor();
      final r = radii[i0] * (1 - frac) + radii[i1] * frac;
      if (dist <= r) cells.add('$x,$y');
    }
  }
  if (cells.length < 6) return _diamond(w, h, random);
  return cells;
}
