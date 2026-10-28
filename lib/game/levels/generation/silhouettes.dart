import 'dart:math';

import '../grid_cell_key.dart';
import 'layout_mask.dart';

/// High-level visual read of a [SilhouetteId] for diversity / ledger rules.
///
/// Geometric “lattice” silhouettes (rectangle / polyomino-style crosses and
/// diamonds / rings) are grouped so ledger novelty cannot be fooled by hopping
/// between near-identical geometric ids.
enum SilhouetteVisualFamily {
  geometricLattice,
  organic,
  archipelago,
  corridor,
}

/// Maps each silhouette id to its visual family.
SilhouetteVisualFamily silhouetteVisualFamily(SilhouetteId id) {
  switch (id) {
    case SilhouetteId.rectangle:
    case SilhouetteId.diamond:
    case SilhouetteId.cross:
    case SilhouetteId.ring:
      return SilhouetteVisualFamily.geometricLattice;
    case SilhouetteId.organicBlob:
    case SilhouetteId.asymmetric:
      return SilhouetteVisualFamily.organic;
    case SilhouetteId.archipelago:
      return SilhouetteVisualFamily.archipelago;
    case SilhouetteId.corridor:
      return SilhouetteVisualFamily.corridor;
  }
}

/// Eight silhouette buckets used by the Director and packed into the
/// Diversity Ledger's 23-bit fingerprint (§4.5 bits 0–2).
///
/// The first six match the explicit list in Phase 3 of §9
/// (rectangle, ring, archipelago, corridor, organic blob, asymmetric as
/// stretch). [diamond] and [cross] fill the remaining two slots so the
/// fingerprint uses the full 3-bit field.
enum SilhouetteId {
  rectangle,
  ring,
  archipelago,
  corridor,
  organicBlob,
  asymmetric,
  diamond,
  cross,
}

/// Concrete-shape pools per [SilhouetteId].
///
/// Each silhouette id resolves to *one of several* concrete renderings instead
/// of a single hardcoded mask. This is what wires the previously-orphaned
/// [LayoutMaskKind] shapes (vShape, pentagon, cShape, zigzag, spiral,
/// hollowDiamond, xShape, scatteredHoles, …) into the Director pipeline and
/// breaks the "plus / square / L / diamond on repeat" feel.
///
/// A `null` entry means "use the id's native custom builder" (the full
/// rectangle, the bespoke archipelago, or the bespoke corridor). The
/// [SilhouetteVisualFamily] of an id is unchanged by the concrete pick, so the
/// Diversity Ledger's family guardrails keep working — the ledger's spatial
/// fingerprint still separates the concrete results as genuinely distinct.
const Map<SilhouetteId, List<LayoutMaskKind?>> silhouetteShapePool = {
  // Always the full board (preserves the `playCells == null` fallback path).
  SilhouetteId.rectangle: [null],
  // "Square with a hole" → also the C/notch and the Manhattan annulus.
  SilhouetteId.ring: [
    LayoutMaskKind.donut,
    LayoutMaskKind.cShape,
    LayoutMaskKind.hollowDiamond,
  ],
  // Bespoke clusters, plus a mostly-filled scatter for a different read.
  SilhouetteId.archipelago: [null, LayoutMaskKind.scatteredHoles],
  // Straight band, winding band, or spiral arm.
  SilhouetteId.corridor: [null, LayoutMaskKind.zigzag, LayoutMaskKind.spiral],
  SilhouetteId.organicBlob: [LayoutMaskKind.randomBlob],
  // The big variety win: L / V / pentagon / wavy band instead of L-on-repeat.
  SilhouetteId.asymmetric: [
    LayoutMaskKind.lShape,
    LayoutMaskKind.vShape,
    LayoutMaskKind.pentagon,
    LayoutMaskKind.zigzag,
  ],
  // Diamond plate or hollow diamond.
  SilhouetteId.diamond: [LayoutMaskKind.diamond, LayoutMaskKind.hollowDiamond],
  // Plus sign or its 45°-rotated cousin, the X.
  SilhouetteId.cross: [LayoutMaskKind.cross, LayoutMaskKind.xShape],
};

/// Builds the cell-key mask for [id] on a `gridWidth × gridHeight` board.
///
/// Returns null when the resulting silhouette would be too small to support a
/// reasonable Retrograde construction (caller should swap silhouette or
/// rectangle-fallback). Always succeeds for [SilhouetteId.rectangle].
///
/// When [varied] is true (the default, procedural path) the concrete rendering
/// is sampled from [silhouetteShapePool] so the same id reads differently
/// across levels. When false (hand-authored seeds) the canonical first pool
/// entry is used and *no* extra entropy is drawn from [random], keeping seeded
/// levels byte-stable.
///
/// [jitterSeed] (non-zero only on the varied path) seeds a *level-isolated* RNG
/// used purely for intra-shape jitter (e.g. diamond radius/centre, cross arm
/// thickness, donut hole). It never draws from [random], so the main generation
/// stream — and therefore node placement, evaluator metrics, and seed
/// byte-stability — is unchanged; only the concrete silhouette outline varies.
Set<int>? buildSilhouetteMask({
  required SilhouetteId id,
  required int gridWidth,
  required int gridHeight,
  required Random random,
  int minCells = 6,
  bool varied = true,
  int jitterSeed = 0,
}) {
  final pool = silhouetteShapePool[id] ?? const [null];
  final LayoutMaskKind? kind =
      varied ? pool[random.nextInt(pool.length)] : pool.first;
  // Per-(level, id, kind) jitter RNG, independent of `random`. Disabled (null)
  // on the seed/canonical path so those masks stay byte-identical.
  final Random? jitter = (varied && jitterSeed != 0 && kind != null)
      ? Random(jitterSeed * 1000003 + id.index * 131 + kind.index * 17)
      : null;

  Set<int>? cells;
  if (kind != null) {
    cells =
        _fromLayoutMask(kind, gridWidth, gridHeight, random, jitter: jitter);
  } else {
    switch (id) {
      case SilhouetteId.rectangle:
        cells = _allCells(gridWidth, gridHeight);
      case SilhouetteId.archipelago:
        cells = _archipelago(gridWidth, gridHeight, random);
      case SilhouetteId.corridor:
        cells = _corridor(gridWidth, gridHeight, random);
      default:
        // Pools only use `null` for the three ids above; any other id with a
        // null pick falls back to the full board so the caller still has room.
        cells = _allCells(gridWidth, gridHeight);
    }
  }
  if (cells == null || cells.length < minCells) return null;
  return cells;
}

/// Converts a `Set<int>` cell-key mask back to the `Set<String>?` form that
/// [LevelData.playCells] expects. Returns null for the full rectangle (so the
/// caller can use the legacy `playCells == null` invariant).
Set<String>? silhouetteToPlayCells(
  Set<int> mask, {
  required int gridWidth,
  required int gridHeight,
}) {
  if (mask.length == gridWidth * gridHeight) return null;
  final out = <String>{};
  for (final key in mask) {
    final x = key & 0xffff;
    final y = (key >> 16) & 0xffff;
    out.add('$x,$y');
  }
  return out;
}

/// Set of all cells in a rectangle.
Set<int> _allCells(int w, int h) {
  final out = <int>{};
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      out.add(gridCellKey(x, y));
    }
  }
  return out;
}

Set<int>? _fromLayoutMask(
  LayoutMaskKind kind,
  int w,
  int h,
  Random random, {
  Random? jitter,
}) {
  final mask = buildLayoutMask(kind, w, h, random: random, jitter: jitter);
  if (mask == null || mask.isEmpty) return null;
  final out = <int>{};
  for (final s in mask) {
    final comma = s.indexOf(',');
    if (comma < 0) continue;
    final x = int.parse(s.substring(0, comma));
    final y = int.parse(s.substring(comma + 1));
    out.add(gridCellKey(x, y));
  }
  return out;
}

/// Three small clusters separated by gaps — "archipelago".
Set<int> _archipelago(int w, int h, Random random) {
  final out = <int>{};
  final clusterRadius = max(1, min(w, h) ~/ 5);
  // Three jittered centres roughly evenly spaced along the grid's long axis.
  final centres = <Point<int>>[];
  if (w >= h) {
    final y = h ~/ 2 + (random.nextBool() ? 0 : 1);
    centres.add(Point(w ~/ 5, y));
    centres.add(Point(w ~/ 2, y + (random.nextBool() ? 0 : -1)));
    centres.add(Point(w - w ~/ 5 - 1, y));
  } else {
    final x = w ~/ 2 + (random.nextBool() ? 0 : 1);
    centres.add(Point(x, h ~/ 5));
    centres.add(Point(x + (random.nextBool() ? 0 : -1), h ~/ 2));
    centres.add(Point(x, h - h ~/ 5 - 1));
  }
  for (final c in centres) {
    for (var dy = -clusterRadius; dy <= clusterRadius; dy++) {
      for (var dx = -clusterRadius; dx <= clusterRadius; dx++) {
        if (dx * dx + dy * dy > clusterRadius * clusterRadius) continue;
        final x = c.x + dx;
        final y = c.y + dy;
        if (x < 0 || x >= w || y < 0 || y >= h) continue;
        out.add(gridCellKey(x, y));
      }
    }
  }
  return out;
}

/// Thin horizontal or vertical band — "corridor".
Set<int> _corridor(int w, int h, Random random) {
  final out = <int>{};
  final vertical = w < h ? true : (h < w ? false : random.nextBool());
  if (vertical) {
    final bandWidth = max(2, w ~/ 3);
    final x0 = (w - bandWidth) ~/ 2;
    for (var y = 0; y < h; y++) {
      for (var x = x0; x < x0 + bandWidth; x++) {
        if (x >= 0 && x < w) out.add(gridCellKey(x, y));
      }
    }
  } else {
    final bandHeight = max(2, h ~/ 3);
    final y0 = (h - bandHeight) ~/ 2;
    for (var y = y0; y < y0 + bandHeight; y++) {
      for (var x = 0; x < w; x++) {
        if (y >= 0 && y < h) out.add(gridCellKey(x, y));
      }
    }
  }
  return out;
}
