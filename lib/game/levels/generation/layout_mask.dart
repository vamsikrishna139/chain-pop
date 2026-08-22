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

  /// Checkerboard pattern (alternating cells).
  checkerboard,

  /// Full grid with randomly scattered holes.
  scatteredHoles,

  /// Archimedean spiral band from the center (polar band; matches gemini_code
  /// visual without the unused grid-walk stub).
  spiral,

  /// Thick Manhattan-diamond boundary with hollow center.
  hollowDiamond,

  /// Thick diagonal X reaching toward the corners.
  xShape,
}

/// Builds the set of playable cell keys `"x,y"` for [kind] on a `w`×`h` grid.
///
/// When [kind] is [LayoutMaskKind.fullRect], returns `null` (meaning "no mask").
Set<String>? buildLayoutMask(
  LayoutMaskKind kind,
  int w,
  int h, {
  Random? random,
  Random? jitter,
}) {
  switch (kind) {
    case LayoutMaskKind.fullRect:
      return null;
    case LayoutMaskKind.vShape:
      return _vShape(w, h, random, jitter: jitter);
    case LayoutMaskKind.pentagon:
      return _pentagonCells(w, h, random, jitter: jitter);
    case LayoutMaskKind.cShape:
      return _cShape(w, h, random, jitter: jitter);
    case LayoutMaskKind.diamond:
      return _diamond(w, h, random, jitter: jitter);
    case LayoutMaskKind.cross:
      return _cross(w, h, random, jitter: jitter);
    case LayoutMaskKind.lShape:
      return _lShapeCells(w, h, random, jitter: jitter);
    case LayoutMaskKind.donut:
      return _donut(w, h, random, jitter: jitter);
    case LayoutMaskKind.zigzag:
      return _zigzag(w, h, random, jitter: jitter);
    case LayoutMaskKind.randomBlob:
      return _randomBlob(w, h, random, jitter: jitter);
    case LayoutMaskKind.checkerboard:
      return _checkerboard(w, h, random, jitter: jitter);
    case LayoutMaskKind.scatteredHoles:
      return _scatteredHoles(w, h, random, jitter: jitter);
    case LayoutMaskKind.spiral:
      return _spiralCells(w, h, random, jitter: jitter);
    case LayoutMaskKind.hollowDiamond:
      return _hollowDiamond(w, h, random, jitter: jitter);
    case LayoutMaskKind.xShape:
      return _xShape(w, h, random, jitter: jitter);
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
      return random.nextDouble() < 0.85;
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
    LayoutMaskKind.checkerboard,
    LayoutMaskKind.scatteredHoles,
    LayoutMaskKind.spiral,
    LayoutMaskKind.hollowDiamond,
    LayoutMaskKind.xShape,
  ];
  return all[random.nextInt(all.length)];
}

// ═══════════════════════════════════════════════════════════════════════════
// Original shapes
// ═══════════════════════════════════════════════════════════════════════════

/// Wedge opening toward the top.
///
/// [jitter] (level-isolated RNG) nudges the apex column and varies the wedge's
/// steepness, so the V is not the same fixed 45-degree cone every level. It
/// draws nothing from the main [random] stream, so non-jittered output is
/// byte-identical to the original.
Set<String> _vShape(int w, int h, Random? random, {Random? jitter}) {
  final cells = <String>{};
  var cx = w ~/ 2;
  if (random != null && w > 4 && random.nextBool()) {
    cx = cx + (random.nextBool() ? 1 : -1);
    cx = cx.clamp(1, w - 2);
  }
  final mirror = random?.nextBool() ?? false;
  final j = jitter;
  if (j != null && w > 4) {
    cx = (cx + j.nextInt(3) - 1).clamp(1, w - 2);
  }
  // 1.0 reproduces the original one-cell-per-row flare exactly.
  final slope = j == null ? 1.0 : 0.75 + j.nextDouble() * 0.6;
  for (var y = 0; y < h; y++) {
    final distFromBottom = h - 1 - y;
    final flare = (distFromBottom * slope).floor();
    final halfWidth = min(flare, max(w ~/ 2, 1));
    for (var dx = -halfWidth; dx <= halfWidth; dx++) {
      var x = cx + dx;
      if (mirror) x = w - 1 - x;
      if (x >= 0 && x < w) cells.add('$x,$y');
    }
  }
  return cells;
}

/// Irregular pentagon rasterised from a [Path].
///
/// [jitter] (level-isolated RNG) slides the apex off-centre, moves the
/// shoulder line up or down and widens or narrows the base, turning one fixed
/// pentagon into a family of them. Draws nothing from the main [random]
/// stream; the original wobble draw is preserved verbatim.
Set<String> _pentagonCells(int w, int h, Random? random, {Random? jitter}) {
  final path = Path();
  // Preserve the original main-stream draw so non-jittered output is unchanged.
  final wobble = (random?.nextDouble() ?? 0.5) * 0.08;
  final j = jitter;
  final apex = j == null ? 0.5 : 0.34 + j.nextDouble() * 0.32;
  final midY = j == null ? 0.42 : 0.32 + j.nextDouble() * 0.22;
  // Biased below the original 0.22 so jitter widens the base more often
  // than it narrows it; a narrower base costs cells and risks a fallback.
  final baseIn = j == null ? 0.22 : 0.10 + j.nextDouble() * 0.14;
  final x0 = w * (0.08 + wobble);
  final x1 = w * (0.92 - wobble);
  final yTop = h * (0.18 + wobble * 0.5);
  final yMid = h * midY;
  final yBot = h * (0.92 - wobble * 0.5);
  path.moveTo(w * apex, yTop);
  path.lineTo(x1, yMid);
  path.lineTo(w * (1 - baseIn), yBot);
  path.lineTo(w * baseIn, yBot);
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
    return _vShape(w, h, random, jitter: jitter);
  }
  return cells;
}

/// Thick frame with a rectangular void; a single-cell-wide passage links void to one edge.
Set<String> _cShape(int w, int h, Random? random, {Random? jitter}) {
  final cells = <String>{};
  final j = jitter;
  // Void size varies +/-25% per axis and slides one cell off-centre; the frame
  // always survives because the void is clamped to w-2 / h-2.
  final iw = j == null
      ? max(2, w ~/ 3)
      : (((w / 3) * (0.75 + j.nextDouble() * 0.6)).round()).clamp(2, max(2, w - 2));
  final ih = j == null
      ? max(2, h ~/ 3)
      : (((h / 3) * (0.75 + j.nextDouble() * 0.6)).round()).clamp(2, max(2, h - 2));
  final ox = j == null
      ? (w - iw) ~/ 2
      : ((w - iw) ~/ 2 + j.nextInt(3) - 1).clamp(1, max(1, w - iw - 1));
  final oy = j == null
      ? (h - ih) ~/ 2
      : ((h - ih) ~/ 2 + j.nextInt(3) - 1).clamp(1, max(1, h - ih - 1));
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
///
/// [jitter] (a level-isolated RNG that does not touch the main generation
/// stream) varies the centre and gives the two axes independent radii, so the
/// diamond reads as a lozenge/off-centre rhombus instead of the same centred
/// octagon every level.
Set<String> _diamond(int w, int h, Random? random, {Random? jitter}) {
  final cells = <String>{};
  // Preserve the original main-stream draw so non-jittered output is unchanged.
  final wobble = (random?.nextDouble() ?? 0.5) * 0.15;
  final j = jitter;
  final cx = w / 2.0 + (j == null ? 0.0 : (j.nextDouble() - 0.5) * w * 0.18);
  final cy = h / 2.0 + (j == null ? 0.0 : (j.nextDouble() - 0.5) * h * 0.18);
  final base = min(w, h) / 2.0 - 0.3 + wobble;
  final rx = j == null ? base : base * (0.78 + j.nextDouble() * 0.5);
  final ry = j == null ? base : base * (0.78 + j.nextDouble() * 0.5);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      // Weighted Manhattan ball: |dx|/rx + |dy|/ry ≤ 1 (reduces to the plain
      // Manhattan ball when rx == ry == base).
      if ((x + 0.5 - cx).abs() / rx + (y + 0.5 - cy).abs() / ry <= 1.0) {
        cells.add('$x,$y');
      }
    }
  }
  if (cells.length < 6) return _vShape(w, h, random);
  return cells;
}

/// Plus / cross — two intersecting bars.
///
/// [jitter] (level-isolated RNG) varies each arm's thickness independently and
/// nudges the centre, so the plus isn't the same fixed glyph every level. It
/// draws nothing from the main [random] stream, so non-jittered output is
/// byte-identical to the original fixed 38%-arm cross.
Set<String> _cross(int w, int h, Random? random, {Random? jitter}) {
  final cells = <String>{};
  final j = jitter;
  final fracW = j == null ? 0.38 : 0.26 + j.nextDouble() * 0.26; // 0.26–0.52
  final fracH = j == null ? 0.38 : 0.26 + j.nextDouble() * 0.26;
  final armW = max(1, (w * fracW).round());
  final armH = max(1, (h * fracH).round());
  final offX = j == null ? 0 : j.nextInt(3) - 1; // -1, 0, +1
  final offY = j == null ? 0 : j.nextInt(3) - 1;
  final cx = (w ~/ 2 + offX).clamp(1, max(1, w - 2));
  final cy = (h ~/ 2 + offY).clamp(1, max(1, h - 2));
  final halfW = armW ~/ 2;
  final halfH = armH ~/ 2;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if ((x - cx).abs() <= halfW || (y - cy).abs() <= halfH) {
        cells.add('$x,$y');
      }
    }
  }
  if (cells.length < 9) return _diamond(w, h, random, jitter: jitter);
  return cells;
}

/// L-shape — two perpendicular bars; rotated randomly among 4 orientations.
///
/// [jitter] (level-isolated RNG) gives the two bars independent thicknesses,
/// so the L reads as a genuine elbow rather than the same symmetric 42% pair
/// every level. Draws nothing from the main [random] stream.
Set<String> _lShapeCells(int w, int h, Random? random, {Random? jitter}) {
  final cells = <String>{};
  final j = jitter;
  final fracW = j == null ? 0.42 : 0.30 + j.nextDouble() * 0.28;
  final fracH = j == null ? 0.42 : 0.30 + j.nextDouble() * 0.28;
  final barW = max(2, (w * fracW).round());
  final barH = max(2, (h * fracH).round());
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
  if (cells.length < 9) return _diamond(w, h, random, jitter: jitter);
  return cells;
}

/// Donut — full rectangle with a rectangular hole.
///
/// [jitter] (level-isolated RNG) varies the hole's size on each axis and slides
/// it off-centre, so the ring isn't the same concentric frame every level.
/// The original main-stream draw is preserved for the non-jittered path.
Set<String> _donut(int w, int h, Random? random, {Random? jitter}) {
  final cells = <String>{};
  final wobble = (random?.nextDouble() ?? 0.5) * 0.06;
  final j = jitter;
  final fracW = j == null ? 0.32 + wobble : 0.22 + j.nextDouble() * 0.28;
  final fracH = j == null ? 0.32 + wobble : 0.22 + j.nextDouble() * 0.28;
  final holeW = max(1, min(w - 2, (w * fracW).round()));
  final holeH = max(1, min(h - 2, (h * fracH).round()));
  final maxOx = w - holeW;
  final maxOy = h - holeH;
  final ox = j == null ? maxOx ~/ 2 : j.nextInt(maxOx + 1);
  final oy = j == null ? maxOy ~/ 2 : j.nextInt(maxOy + 1);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final inHole = x >= ox && x < ox + holeW && y >= oy && y < oy + holeH;
      if (!inHole) cells.add('$x,$y');
    }
  }
  return cells;
}

/// Sinusoidal band — a wavy stripe across the grid.
///
/// [jitter] (level-isolated RNG) varies the band's thickness, the wave's
/// amplitude and its starting phase, so the stripe does not cross the board at
/// the same place every level. Draws nothing from the main [random] stream;
/// the period and orientation draws are preserved verbatim.
Set<String> _zigzag(int w, int h, Random? random, {Random? jitter}) {
  final cells = <String>{};
  final j = jitter;
  final bandWidth = j == null
      ? max(2, min(w, h) ~/ 3)
      : max(2, ((min(w, h) / 3) * (0.75 + j.nextDouble() * 0.7)).round());
  final periods = 2 + (random?.nextInt(2) ?? 0);
  final vertical = random?.nextBool() ?? false;
  final amp = j == null ? 0.28 : 0.18 + j.nextDouble() * 0.22;
  final phase = j == null ? 0.0 : j.nextDouble() * pi;
  final span = vertical ? w : h;
  final length = vertical ? h : w;

  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final progress = (vertical ? y : x) / max(1, length);
      final perp = (vertical ? x : y).toDouble();
      final center =
          span / 2.0 + sin(progress * periods * pi + phase) * span * amp;
      if ((perp - center).abs() < bandWidth) {
        cells.add('$x,$y');
      }
    }
  }
  if (cells.length < 9) return _diamond(w, h, random, jitter: jitter);
  return cells;
}

/// Organic blob — polar shape with randomly varying radii at 8 angles,
/// linearly interpolated for smooth edges.
/// [jitter] (level-isolated RNG) nudges the centre and re-scales each angular
/// radius independently, so two blobs built from the same main-stream draws
/// still read as different organisms. Draws nothing from the main [random]
/// stream; all eight radius draws are preserved verbatim.
Set<String> _randomBlob(int w, int h, Random? random, {Random? jitter}) {
  final cells = <String>{};
  final rng = random ?? Random();
  final j = jitter;
  final cx = w / 2.0 + (j == null ? 0.0 : (j.nextDouble() - 0.5) * w * 0.14);
  final cy = h / 2.0 + (j == null ? 0.0 : (j.nextDouble() - 0.5) * h * 0.14);
  final baseR = min(w, h) / 2.2;
  const nAngles = 8;
  final radii =
      List.generate(nAngles, (_) => baseR * (0.5 + rng.nextDouble() * 0.7));
  if (j != null) {
    for (var i = 0; i < nAngles; i++) {
      radii[i] = radii[i] * (0.85 + j.nextDouble() * 0.4);
    }
  }

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
  if (cells.length < 6) return _diamond(w, h, random, jitter: jitter);
  return cells;
}

/// Checkerboard — alternating cells (many local gaps; high perimeter).
///
/// [jitter] (level-isolated RNG) varies the tile size, so the board can also
/// present as 2x2 blocks instead of only single-cell chequering. Fill stays at
/// ~50% either way, so the size envelope is unchanged. Draws nothing from the
/// main [random] stream; the phase draw is preserved verbatim.
Set<String> _checkerboard(int w, int h, Random? random, {Random? jitter}) {
  final cells = <String>{};
  final offset = random?.nextInt(2) ?? 0;
  final j = jitter;
  // 1 reproduces the original single-cell chequer exactly.
  final block = j == null ? 1 : 1 + j.nextInt(2);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (((x ~/ block) + (y ~/ block)) % 2 == offset) {
        cells.add('$x,$y');
      }
    }
  }
  return cells;
}

/// Full grid with roughly 20–30% random holes removed (70–85% filled).
/// [jitter] (level-isolated RNG) shifts the fill rate within the same 62-92%
/// envelope, so the hole density varies per level. It changes no main-stream
/// draw and consumes none of them: the per-cell rolls below still come from
/// [random] in the same order and the same count.
Set<String> _scatteredHoles(int w, int h, Random? random, {Random? jitter}) {
  final cells = <String>{};
  final rng = random ?? Random();
  final fillRate = 0.7 + rng.nextDouble() * 0.15;
  final j = jitter;
  final rate = j == null
      ? fillRate
      : (fillRate + (j.nextDouble() - 0.5) * 0.16).clamp(0.62, 0.92).toDouble();
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (rng.nextDouble() < rate) {
        cells.add('$x,$y');
      }
    }
  }
  if (cells.length < 9) return _diamond(w, h, random, jitter: jitter);
  return cells;
}

/// Archimedean spiral band using polar math (compact, deterministic).
///
/// [jitter] (level-isolated RNG) varies the arm spacing, the band's angular
/// width and the twist rate, and nudges the centre. This builder previously
/// ignored [random] entirely, so every spiral in the game was the same glyph;
/// it still draws nothing from the main stream, so the non-jittered path is
/// byte-identical to that original.
Set<String> _spiralCells(int w, int h, Random? random, {Random? jitter}) {
  final cells = <String>{};
  final j = jitter;
  final cx = w / 2.0 + (j == null ? 0.0 : (j.nextDouble() - 0.5) * w * 0.10);
  final cy = h / 2.0 + (j == null ? 0.0 : (j.nextDouble() - 0.5) * h * 0.10);
  final rScale = j == null ? 1.5 : 1.2 + j.nextDouble() * 0.7;
  final twist = j == null ? 0.5 : 0.32 + j.nextDouble() * 0.36;
  // Area-preserving: fill is ~bandFrac/1.5, so the floor stays near the
  // original 0.8 while the twist/scale/centre carry the variety.
  final bandFrac = j == null ? 0.8 : 0.74 + j.nextDouble() * 0.26;
  for (var ty = 0; ty < h; ty++) {
    for (var tx = 0; tx < w; tx++) {
      final fx = tx + 0.5 - cx;
      final fy = ty + 0.5 - cy;
      final r = sqrt(fx * fx + fy * fy);
      final theta = atan2(fy, fx);
      final scaledR = r * rScale;
      final normalized = (scaledR - theta * twist) % (pi * 1.5);
      if (normalized < pi * bandFrac) {
        cells.add('$tx,$ty');
      }
    }
  }
  if (cells.length < 9) return _diamond(w, h, random, jitter: jitter);
  return cells;
}

/// Hollow diamond — Manhattan annulus.
///
/// [jitter] (level-isolated RNG) varies the band thickness (inner-radius ratio)
/// and nudges the centre. Draws nothing from the main [random] stream.
Set<String> _hollowDiamond(int w, int h, Random? random, {Random? jitter}) {
  final cells = <String>{};
  final j = jitter;
  final cx = w / 2.0 + (j == null ? 0.0 : (j.nextDouble() - 0.5) * w * 0.12);
  final cy = h / 2.0 + (j == null ? 0.0 : (j.nextDouble() - 0.5) * h * 0.12);
  final radius = min(w, h) / 2.0;
  final innerRatio = j == null ? 0.4 : 0.30 + j.nextDouble() * 0.30; // 0.30–0.60
  final innerRadius = max(1.0, radius * innerRatio);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final dist = (x + 0.5 - cx).abs() + (y + 0.5 - cy).abs();
      if (dist <= radius && dist >= innerRadius) {
        cells.add('$x,$y');
      }
    }
  }
  if (cells.length < 9) return _donut(w, h, random, jitter: jitter);
  return cells;
}

/// X shape — thick diagonals.
///
/// [jitter] (level-isolated RNG) varies the diagonal thickness. Draws nothing
/// from the main [random] stream.
Set<String> _xShape(int w, int h, Random? random, {Random? jitter}) {
  final cells = <String>{};
  final cx = w / 2.0;
  final cy = h / 2.0;
  final j = jitter;
  final thickFrac = j == null ? 0.15 : 0.11 + j.nextDouble() * 0.12; // 0.11–0.23
  final thickness = max(1.0, min(w, h) * thickFrac);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final normX = (x + 0.5 - cx) / w;
      final normY = (y + 0.5 - cy) / h;
      final d1 = (normX - normY).abs() * w;
      final d2 = (normX + normY).abs() * w;
      if (d1 <= thickness || d2 <= thickness) {
        cells.add('$x,$y');
      }
    }
  }
  if (cells.length < 9) return _cross(w, h, random, jitter: jitter);
  return cells;
}
