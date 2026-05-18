import '../grid_cell_key.dart';

/// Incremental data structure tracking the **frontier** — empty silhouette
/// cells that are either adjacent to an already-placed node or on the
/// silhouette's outer boundary (touching the grid edge or a non-silhouette
/// neighbour).
///
/// This is the reviewer's perf optimisation that cuts candidate enumeration
/// in [RetrogradeConstructor] from O(emptyCells) per step to O(frontier).
///
/// All updates are O(neighbourhood) — typically 4 (or 8 with diagonals).
class FrontierSet {
  /// Width of the bounding grid.
  final int gridWidth;

  /// Height of the bounding grid.
  final int gridHeight;

  /// The silhouette mask — set of cell keys eligible to hold nodes.
  final Set<int> silhouette;

  /// When true, 8-connected adjacency expands the frontier diagonally too.
  final bool eightConnected;

  /// Cell keys currently in the frontier.
  final Set<int> _cells = <int>{};

  /// Cell keys currently treated as placed (occupied by nodes).
  final Set<int> _placed = <int>{};

  /// For each silhouette cell, the count of placed neighbours. Used to decide
  /// when a cell should leave the frontier on rollback. Cells that are only
  /// in the frontier because they are boundary cells have no entry here.
  final Map<int, int> _placedNeighbourCount = <int, int>{};

  /// Builds an initial frontier seeded with the silhouette's outer boundary
  /// (cells that touch either the grid edge or a non-silhouette neighbour).
  FrontierSet({
    required this.gridWidth,
    required this.gridHeight,
    required this.silhouette,
    this.eightConnected = false,
  }) {
    for (final cell in silhouette) {
      if (_isBoundary(cell)) _cells.add(cell);
    }
  }

  /// Cells currently in the frontier.
  Iterable<int> get cells => _cells;

  /// Number of cells currently in the frontier.
  int get length => _cells.length;

  /// Whether [cell] is in the frontier.
  bool contains(int cell) => _cells.contains(cell);

  /// Whether [cell] has been marked placed.
  bool isPlaced(int cell) => _placed.contains(cell);

  /// Marks [cell] as placed and expands the frontier to include its
  /// silhouette-cell neighbours.
  void addPlaced(int cell) {
    _placed.add(cell);
    _cells.remove(cell);
    final x = cell & 0xffff;
    final y = (cell >> 16) & 0xffff;
    for (final off in _offsets) {
      final nx = x + off.$1;
      final ny = y + off.$2;
      if (nx < 0 || nx >= gridWidth || ny < 0 || ny >= gridHeight) continue;
      final nkey = gridCellKey(nx, ny);
      if (!silhouette.contains(nkey)) continue;
      _placedNeighbourCount[nkey] = (_placedNeighbourCount[nkey] ?? 0) + 1;
      if (!_placed.contains(nkey)) _cells.add(nkey);
    }
  }

  /// Rolls back a placement: marks [cell] as no longer placed, contracts the
  /// frontier where neighbour-counts drop to zero, and re-adds [cell] itself
  /// if it should be in the frontier (boundary or still has placed neighbours).
  void removePlaced(int cell) {
    _placed.remove(cell);
    final x = cell & 0xffff;
    final y = (cell >> 16) & 0xffff;
    for (final off in _offsets) {
      final nx = x + off.$1;
      final ny = y + off.$2;
      if (nx < 0 || nx >= gridWidth || ny < 0 || ny >= gridHeight) continue;
      final nkey = gridCellKey(nx, ny);
      if (!silhouette.contains(nkey)) continue;
      final count = _placedNeighbourCount[nkey] ?? 0;
      if (count <= 1) {
        _placedNeighbourCount.remove(nkey);
        if (!_placed.contains(nkey) && !_isBoundary(nkey)) {
          _cells.remove(nkey);
        }
      } else {
        _placedNeighbourCount[nkey] = count - 1;
      }
    }
    if (silhouette.contains(cell)) {
      if (_isBoundary(cell) || (_placedNeighbourCount[cell] ?? 0) > 0) {
        _cells.add(cell);
      }
    }
  }

  bool _isBoundary(int cell) {
    final x = cell & 0xffff;
    final y = (cell >> 16) & 0xffff;
    for (final off in _offsets) {
      final nx = x + off.$1;
      final ny = y + off.$2;
      if (nx < 0 || nx >= gridWidth || ny < 0 || ny >= gridHeight) return true;
      if (!silhouette.contains(gridCellKey(nx, ny))) return true;
    }
    return false;
  }

  /// 4- or 8-connected neighbour offsets.
  List<(int, int)> get _offsets {
    if (eightConnected) {
      return const [
        (-1, 0),
        (1, 0),
        (0, -1),
        (0, 1),
        (-1, -1),
        (1, -1),
        (-1, 1),
        (1, 1),
      ];
    }
    return const [
      (-1, 0),
      (1, 0),
      (0, -1),
      (0, 1),
    ];
  }
}
