import '../grid_cell_key.dart';
import '../level.dart';

/// Precomputes, for every grid cell and each cardinal direction, the chain of
/// cell keys the ray walks through until it exits the bounding rectangle.
///
/// Querying [hasClearRay] is then O(L) where L is the ray length, capped by
/// `max(gridWidth, gridHeight)`. Compared with re-walking the ray in a switch
/// on every candidate enumeration, this halves the per-call cost on dense
/// boards (no arithmetic, no bounds checks beyond array indexing).
///
/// The table is per-grid (not per-silhouette) so it can be shared by all
/// retrograde attempts that target the same grid dimensions.
class SightlineTable {
  /// Width of the bounding grid this table was built for.
  final int gridWidth;

  /// Height of the bounding grid this table was built for.
  final int gridHeight;

  /// Flat list indexed by `(y * gridWidth + x) * 4 + dir.index`; each entry is
  /// the list of cell keys along the ray from `(x,y)` in `dir` until it exits
  /// the grid (exclusive of the origin cell).
  final List<List<int>> _rays;

  SightlineTable._(this.gridWidth, this.gridHeight, this._rays);

  /// Builds the table for a `gridWidth × gridHeight` rectangular grid.
  factory SightlineTable.forGrid(int gridWidth, int gridHeight) {
    final rays = List<List<int>>.filled(
      gridWidth * gridHeight * 4,
      const <int>[],
      growable: false,
    );
    for (var y = 0; y < gridHeight; y++) {
      for (var x = 0; x < gridWidth; x++) {
        final base = (y * gridWidth + x) * 4;
        for (final dir in Direction.values) {
          rays[base + dir.index] = _walkRay(x, y, dir, gridWidth, gridHeight);
        }
      }
    }
    return SightlineTable._(gridWidth, gridHeight, rays);
  }

  static List<int> _walkRay(
    int x,
    int y,
    Direction dir,
    int gridWidth,
    int gridHeight,
  ) {
    final cells = <int>[];
    var cx = x;
    var cy = y;
    while (true) {
      switch (dir) {
        case Direction.up:
          cy--;
        case Direction.down:
          cy++;
        case Direction.left:
          cx--;
        case Direction.right:
          cx++;
      }
      if (cx < 0 || cx >= gridWidth || cy < 0 || cy >= gridHeight) break;
      cells.add(gridCellKey(cx, cy));
    }
    return List<int>.unmodifiable(cells);
  }

  /// True iff the ray from `(x,y)` along [dir] exits the grid without hitting
  /// any cell whose key is in [occupied].
  bool hasClearRay(int x, int y, Direction dir, Set<int> occupied) {
    final ray = _rays[(y * gridWidth + x) * 4 + dir.index];
    for (final c in ray) {
      if (occupied.contains(c)) return false;
    }
    return true;
  }

  /// Number of cardinal directions whose ray from `(x,y)` is currently clear.
  int clearDirectionCount(int x, int y, Set<int> occupied) {
    var count = 0;
    for (final dir in Direction.values) {
      if (hasClearRay(x, y, dir, occupied)) count++;
    }
    return count;
  }
}
