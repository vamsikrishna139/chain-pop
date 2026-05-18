import 'dart:math';

import '../grid_cell_key.dart';
import '../level.dart';
import 'sightline_table.dart';

/// Motif identifier used both internally and inside the Diversity Ledger's
/// 23-bit fingerprint (§4.5 bits 7–9, 8 slots; `none` reserves slot 0).
///
/// Phase 4 ships four concrete motifs; the remaining slots are intentionally
/// left for Phase 5+ additions (e.g., a Ring-Seed motif) without re-packing
/// the fingerprint.
enum MotifId {
  none,
  escapeChord,
  diamondIntersection,
  clusterKey,
  staircase,
  threeSpokeWheel,
}

/// A single committed reservation produced by a [Motif]. The Retrograde
/// Constructor honours the (position, direction) pair as the start of the
/// construction (= these cells are removed LAST during play, becoming the
/// motif's "finale" the player navigates around).
class MotifReservation {
  final Point<int> position;
  final Direction direction;
  const MotifReservation({required this.position, required this.direction});

  int get cellKey => gridCellKey(position.x, position.y);
}

/// Container for the full motif placement: the identifier, its reservations,
/// and the visual centre (used for diagnostics + future Composition Score).
class MotifPlacement {
  final MotifId id;
  final List<MotifReservation> reservations;
  final Point<int> anchor;
  const MotifPlacement({
    required this.id,
    required this.reservations,
    required this.anchor,
  });
}

/// Abstract motif template. `place` either returns a valid placement on
/// [silhouette] or null when no fit was found (motif transactions are
/// atomic per §4.6 — either the whole block fits or none does).
abstract class Motif {
  MotifId get id;
  String get name;

  MotifPlacement? place({
    required int gridWidth,
    required int gridHeight,
    required Set<int> silhouette,
    required SightlineTable sightlines,
    required Random random,
    int maxAttempts = 24,
  });
}

/// §4.6 catalogue. Phase 4 ships the four motifs called out explicitly in the
/// plan (escape chord, diamond intersection, cluster + key, staircase). The
/// 3-spoke wheel is stubbed for Phase 5 because it needs partial-rotation
/// support the current grid-aligned motif API does not yet expose.
List<Motif> motifCatalogue() => const [
      _EscapeChord(),
      _DiamondIntersection(),
      _ClusterKey(),
      _Staircase(),
    ];

/// Picks one motif uniformly from [motifCatalogue]. Phase 4 sticks to a flat
/// distribution; Phase 5+ can introduce archetype-specific weightings.
Motif sampleMotif(Random random) {
  final cat = motifCatalogue();
  return cat[random.nextInt(cat.length)];
}

// ─────────────────────────────────────────────────────────────────────────
// Concrete motifs
// ─────────────────────────────────────────────────────────────────────────

bool _allInSilhouette(List<Point<int>> cells, Set<int> silhouette) {
  for (final c in cells) {
    if (!silhouette.contains(gridCellKey(c.x, c.y))) return false;
  }
  return true;
}

bool _allDistinct(List<Point<int>> cells) {
  final set = <int>{};
  for (final c in cells) {
    if (!set.add(gridCellKey(c.x, c.y))) return false;
  }
  return true;
}

/// "Escape chord" — a short diagonal of 4–5 cells, each shooting toward the
/// nearest off-grid wall. Visually a chord cutting one corner of the board.
class _EscapeChord implements Motif {
  const _EscapeChord();

  @override
  MotifId get id => MotifId.escapeChord;

  @override
  String get name => 'Escape Chord';

  @override
  MotifPlacement? place({
    required int gridWidth,
    required int gridHeight,
    required Set<int> silhouette,
    required SightlineTable sightlines,
    required Random random,
    int maxAttempts = 24,
  }) {
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final length = 4 + random.nextInt(2); // 4..5
      // Pick a starting corner: each corner aims toward a different wall.
      final corner = random.nextInt(4);
      Direction dir;
      int dx, dy, sx, sy;
      switch (corner) {
        case 0:
          // Top-left corner, chord shoots up.
          dir = Direction.up;
          sx = 1 + random.nextInt(max(1, gridWidth - length - 1));
          sy = 1 + random.nextInt(max(1, gridHeight - 2));
          dx = 1;
          dy = 0;
        case 1:
          dir = Direction.down;
          sx = 1 + random.nextInt(max(1, gridWidth - length - 1));
          sy = (gridHeight - 2)
              .clamp(1, max(1, gridHeight - 2));
          dx = 1;
          dy = 0;
        case 2:
          dir = Direction.left;
          sx = 1 + random.nextInt(max(1, gridWidth - 2));
          sy = 1 + random.nextInt(max(1, gridHeight - length - 1));
          dx = 0;
          dy = 1;
        default:
          dir = Direction.right;
          sx = (gridWidth - 2).clamp(1, max(1, gridWidth - 2));
          sy = 1 + random.nextInt(max(1, gridHeight - length - 1));
          dx = 0;
          dy = 1;
      }
      final cells = <Point<int>>[
        for (var i = 0; i < length; i++) Point(sx + i * dx, sy + i * dy),
      ];
      if (cells.any((c) =>
          c.x < 0 || c.x >= gridWidth || c.y < 0 || c.y >= gridHeight)) {
        continue;
      }
      if (!_allDistinct(cells)) continue;
      if (!_allInSilhouette(cells, silhouette)) continue;
      final reservations = [
        for (final c in cells) MotifReservation(position: c, direction: dir),
      ];
      return MotifPlacement(
        id: id,
        reservations: reservations,
        anchor: cells.first,
      );
    }
    return null;
  }
}

/// "Diamond intersection" — four cells forming a diamond with paired
/// horizontal / vertical exits that cross at the diamond's centre.
class _DiamondIntersection implements Motif {
  const _DiamondIntersection();

  @override
  MotifId get id => MotifId.diamondIntersection;

  @override
  String get name => 'Diamond Intersection';

  @override
  MotifPlacement? place({
    required int gridWidth,
    required int gridHeight,
    required Set<int> silhouette,
    required SightlineTable sightlines,
    required Random random,
    int maxAttempts = 24,
  }) {
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final cx = 2 + random.nextInt(max(1, gridWidth - 4));
      final cy = 2 + random.nextInt(max(1, gridHeight - 4));
      final top = Point<int>(cx, cy - 1);
      final bottom = Point<int>(cx, cy + 1);
      final left = Point<int>(cx - 1, cy);
      final right = Point<int>(cx + 1, cy);
      final cells = [top, bottom, left, right];
      if (cells.any((c) =>
          c.x < 0 || c.x >= gridWidth || c.y < 0 || c.y >= gridHeight)) {
        continue;
      }
      if (!_allInSilhouette(cells, silhouette)) continue;
      final reservations = [
        MotifReservation(position: top, direction: Direction.up),
        MotifReservation(position: bottom, direction: Direction.down),
        MotifReservation(position: left, direction: Direction.left),
        MotifReservation(position: right, direction: Direction.right),
      ];
      return MotifPlacement(
        id: id,
        reservations: reservations,
        anchor: Point<int>(cx, cy),
      );
    }
    return null;
  }
}

/// "Cluster + key" — a 2×2 cluster pointing in all four directions plus a
/// distant "key" cell that controls the cluster's release.
class _ClusterKey implements Motif {
  const _ClusterKey();

  @override
  MotifId get id => MotifId.clusterKey;

  @override
  String get name => 'Cluster + Key';

  @override
  MotifPlacement? place({
    required int gridWidth,
    required int gridHeight,
    required Set<int> silhouette,
    required SightlineTable sightlines,
    required Random random,
    int maxAttempts = 24,
  }) {
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (gridWidth < 5 || gridHeight < 5) continue;
      final cx = 1 + random.nextInt(gridWidth - 3);
      final cy = 1 + random.nextInt(gridHeight - 3);
      final cluster = [
        Point<int>(cx, cy),
        Point<int>(cx + 1, cy),
        Point<int>(cx, cy + 1),
        Point<int>(cx + 1, cy + 1),
      ];
      // Key sits two cells to the right of the cluster on the same row.
      final key = Point<int>(cx + 3, cy);
      if (key.x >= gridWidth) continue;
      final cells = [...cluster, key];
      if (!_allDistinct(cells)) continue;
      if (!_allInSilhouette(cells, silhouette)) continue;
      final reservations = [
        MotifReservation(position: cluster[0], direction: Direction.up),
        MotifReservation(position: cluster[1], direction: Direction.right),
        MotifReservation(position: cluster[2], direction: Direction.left),
        MotifReservation(position: cluster[3], direction: Direction.down),
        MotifReservation(position: key, direction: Direction.right),
      ];
      return MotifPlacement(
        id: id,
        reservations: reservations,
        anchor: Point<int>(cx, cy),
      );
    }
    return null;
  }
}

/// "Staircase" — a chain of N cells stepping diagonally, alternating
/// right / down exit directions so the chain reads as a "staircase".
class _Staircase implements Motif {
  const _Staircase();

  @override
  MotifId get id => MotifId.staircase;

  @override
  String get name => 'Staircase';

  @override
  MotifPlacement? place({
    required int gridWidth,
    required int gridHeight,
    required Set<int> silhouette,
    required SightlineTable sightlines,
    required Random random,
    int maxAttempts = 24,
  }) {
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final steps = 4 + random.nextInt(2); // 4..5
      final sx = random.nextInt(max(1, gridWidth - steps));
      final sy = random.nextInt(max(1, gridHeight - steps));
      final cells = <Point<int>>[
        for (var i = 0; i < steps; i++) Point(sx + i, sy + i),
      ];
      if (cells.any((c) =>
          c.x < 0 || c.x >= gridWidth || c.y < 0 || c.y >= gridHeight)) {
        continue;
      }
      if (!_allInSilhouette(cells, silhouette)) continue;
      final reservations = <MotifReservation>[
        for (var i = 0; i < cells.length; i++)
          MotifReservation(
            position: cells[i],
            direction: i.isEven ? Direction.right : Direction.down,
          ),
      ];
      return MotifPlacement(
        id: id,
        reservations: reservations,
        anchor: cells.first,
      );
    }
    return null;
  }
}
