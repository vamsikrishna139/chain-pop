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

/// Builds the cell-key mask for [id] on a `gridWidth × gridHeight` board.
///
/// Returns null when the resulting silhouette would be too small to support a
/// reasonable Retrograde construction (caller should swap silhouette or
/// rectangle-fallback). Always succeeds for [SilhouetteId.rectangle].
Set<int>? buildSilhouetteMask({
  required SilhouetteId id,
  required int gridWidth,
  required int gridHeight,
  required Random random,
  int minCells = 6,
}) {
  Set<int>? cells;
  switch (id) {
    case SilhouetteId.rectangle:
      cells = _allCells(gridWidth, gridHeight);
    case SilhouetteId.ring:
      cells = _fromLayoutMask(
          LayoutMaskKind.donut, gridWidth, gridHeight, random);
    case SilhouetteId.archipelago:
      cells = _archipelago(gridWidth, gridHeight, random);
    case SilhouetteId.corridor:
      cells = _corridor(gridWidth, gridHeight, random);
    case SilhouetteId.organicBlob:
      cells = _fromLayoutMask(
          LayoutMaskKind.randomBlob, gridWidth, gridHeight, random);
    case SilhouetteId.asymmetric:
      cells = _fromLayoutMask(
          LayoutMaskKind.lShape, gridWidth, gridHeight, random);
    case SilhouetteId.diamond:
      cells = _fromLayoutMask(
          LayoutMaskKind.diamond, gridWidth, gridHeight, random);
    case SilhouetteId.cross:
      cells = _fromLayoutMask(
          LayoutMaskKind.cross, gridWidth, gridHeight, random);
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
  Random random,
) {
  final mask = buildLayoutMask(kind, w, h, random: random);
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
