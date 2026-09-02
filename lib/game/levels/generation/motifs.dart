import 'dart:math';

import '../grid_cell_key.dart';
import '../level.dart';
import 'difficulty_profile.dart';
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
  lockCluster,
  cascadeHub,
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
      _LockCluster(),
      _EscapeChord(),
      _DiamondIntersection(),
      _ClusterKey(),
      _Staircase(),
      _CascadeHub(),
    ];

Motif? motifById(MotifId id) {
  for (final m in motifCatalogue()) {
    if (m.id == id) return m;
  }
  return null;
}

/// Picks one motif uniformly from [motifCatalogue]. Phase 4 sticks to a flat
/// distribution; Phase 5+ can introduce archetype-specific weightings.
Motif sampleMotif(Random random) {
  final cat = motifCatalogue();
  return cat[random.nextInt(cat.length)];
}

/// Tier-aware motif sampling. Hard/Expert bias toward [MotifId.lockCluster]
/// when [excludeLockCluster] is false.
Motif sampleMotifForTier(
  DifficultyTier tier,
  Random random, {
  bool excludeLockCluster = false,
}) {
  if (tier == DifficultyTier.hard || tier == DifficultyTier.expert) {
    final r = random.nextDouble();
    if (r < 0.40) {
      return motifById(MotifId.cascadeHub)!;
    }
    if (!excludeLockCluster && r < 0.70) {
      return motifById(MotifId.lockCluster)!;
    }
    if (r < 0.85) {
      return motifById(MotifId.diamondIntersection)!;
    }
    return motifById(MotifId.escapeChord)!;
  }
  return sampleMotif(random);
}

// ─────────────────────────────────────────────────────────────────────────
// Concrete motifs
// ─────────────────────────────────────────────────────────────────────────

Point<int> _silhouetteCentroid(Set<int> silhouette) {
  if (silhouette.isEmpty) return const Point(0, 0);
  var sx = 0;
  var sy = 0;
  for (final key in silhouette) {
    sx += key & 0xffff;
    sy += (key >> 16) & 0xffff;
  }
  final n = silhouette.length;
  return Point(sx ~/ n, sy ~/ n);
}

Point<int>? _nearestSilhouetteCell(Set<int> silhouette, Point<int> target) {
  Point<int>? best;
  var bestDist = double.infinity;
  for (final key in silhouette) {
    final x = key & 0xffff;
    final y = (key >> 16) & 0xffff;
    final d = (x - target.x) * (x - target.x) + (y - target.y) * (y - target.y);
    if (d < bestDist) {
      bestDist = d.toDouble();
      best = Point(x, y);
    }
  }
  return best;
}

/// Dense Strategy Phase 2 — center-biased 5–7 cell crunch cluster with
/// cross-blocking ray directions (distinct from [MotifId.clusterKey]).
class _LockCluster implements Motif {
  const _LockCluster();

  @override
  MotifId get id => MotifId.lockCluster;

  @override
  String get name => 'Lock Cluster';

  @override
  MotifPlacement? place({
    required int gridWidth,
    required int gridHeight,
    required Set<int> silhouette,
    required SightlineTable sightlines,
    required Random random,
    int maxAttempts = 24,
  }) {
    if (gridWidth < 5 || gridHeight < 5 || silhouette.length < 7) return null;
    final centroid = _silhouetteCentroid(silhouette);
    final anchor = _nearestSilhouetteCell(silhouette, centroid);
    if (anchor == null) return null;

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final sizeRoll = random.nextInt(3); // 5, 6, or 7 cells
      final targetSize = 5 + sizeRoll;
      final cx = (anchor.x + random.nextInt(5) - 2).clamp(1, gridWidth - 2);
      final cy = (anchor.y + random.nextInt(5) - 2).clamp(1, gridHeight - 2);

      final cells = <Point<int>>[];
      final reservations = <MotifReservation>[];

      // Compact plus (5 cells) with cross-blocking exits.
      final core = <(Point<int>, Direction)>[
        (Point<int>(cx, cy - 1), Direction.up),
        (Point<int>(cx - 1, cy), Direction.left),
        (Point<int>(cx, cy), Direction.right),
        (Point<int>(cx + 1, cy), Direction.left),
        (Point<int>(cx, cy + 1), Direction.down),
      ];
      for (final (cell, dir) in core) {
        cells.add(cell);
        reservations.add(MotifReservation(position: cell, direction: dir));
      }

      // Optional inner entry nodes (inside bbox, not on perimeter).
      if (targetSize >= 6) {
        // Already used — pick offset inner cell instead.
        final entry = Point<int>(cx - 1, cy - 1);

        if (!cells.any((c) => c.x == entry.x && c.y == entry.y)) {
          cells.add(entry);
          reservations.add(
            MotifReservation(position: entry, direction: Direction.down),
          );
        }
      }
      if (targetSize >= 7) {
        final entry = Point<int>(cx + 1, cy + 1);
        if (!cells.any((c) => c.x == entry.x && c.y == entry.y)) {
          cells.add(entry);
          reservations.add(
            MotifReservation(position: entry, direction: Direction.up),
          );
        }
      }

      if (cells.length < 5 || cells.length > 7) continue;
      if (!_allDistinct(cells)) continue;
      if (!_allInSilhouette(cells, silhouette)) continue;
      if (cells.any(
          (c) => c.x < 0 || c.x >= gridWidth || c.y < 0 || c.y >= gridHeight)) {
        continue;
      }

      return MotifPlacement(
        id: id,
        reservations: reservations,
        anchor: Point<int>(cx, cy),
      );
    }
    return null;
  }
}

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
          sy = (gridHeight - 2).clamp(1, max(1, gridHeight - 2));
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
      if (cells.any(
          (c) => c.x < 0 || c.x >= gridWidth || c.y < 0 || c.y >= gridHeight)) {
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
      if (cells.any(
          (c) => c.x < 0 || c.x >= gridWidth || c.y < 0 || c.y >= gridHeight)) {
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
      if (cells.any(
          (c) => c.x < 0 || c.x >= gridWidth || c.y < 0 || c.y >= gridHeight)) {
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

/// "Cascade Hub" — a 5-node cross where 4 adjacent nodes point directly inward
/// toward the central anchor. It establishes a strong geometric gravity well
/// that the `RetrogradeConstructor` and reassignment logic uses to build
/// convergence cascades.
class _CascadeHub implements Motif {
  const _CascadeHub();

  @override
  MotifId get id => MotifId.cascadeHub;

  @override
  String get name => 'Cascade Hub';

  @override
  MotifPlacement? place({
    required int gridWidth,
    required int gridHeight,
    required Set<int> silhouette,
    required SightlineTable sightlines,
    required Random random,
    int maxAttempts = 24,
  }) {
    final centroid = _silhouetteCentroid(silhouette);
    final fallbackAnchor = _nearestSilhouetteCell(silhouette, centroid);
    if (fallbackAnchor == null) return null;

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final cx =
          (fallbackAnchor.x + random.nextInt(5) - 2).clamp(1, gridWidth - 2);
      final cy =
          (fallbackAnchor.y + random.nextInt(5) - 2).clamp(1, gridHeight - 2);

      final dirs = Direction.values.toList()..shuffle(random);
      final openDir = dirs
          .removeLast(); // The direction the center cell will escape through

      final spokes = <Point<int>>[];
      final reservations = <MotifReservation>[];

      // Center cell MUST point towards the open direction
      reservations.add(
          MotifReservation(position: Point<int>(cx, cy), direction: openDir));

      for (final d in dirs) {
        Point<int> p;
        Direction inward;
        switch (d) {
          case Direction.up:
            p = Point(cx, cy - 1);
            inward = Direction.down;
            break;
          case Direction.down:
            p = Point(cx, cy + 1);
            inward = Direction.up;
            break;
          case Direction.left:
            p = Point(cx - 1, cy);
            inward = Direction.right;
            break;
          case Direction.right:
            p = Point(cx + 1, cy);
            inward = Direction.left;
            break;
        }
        spokes.add(p);
        reservations.add(MotifReservation(position: p, direction: inward));
      }

      if (spokes.any(
          (c) => c.x < 0 || c.x >= gridWidth || c.y < 0 || c.y >= gridHeight)) {
        continue;
      }

      if (!_allInSilhouette([...spokes, Point<int>(cx, cy)], silhouette))
        continue;

      // We must reverse the reservations so that spokes are placed first in retrograde
      // (meaning they are removed LAST in forward game) and center is placed last
      // (removed FIRST in forward game). Wait! Center must be removed FIRST in forward game.
      // So center must be placed LAST in retrograde construction.
      // So center should be at the END of the reservations list.
      final placement = MotifPlacement(
        id: id,
        reservations: [
          reservations[1], // spoke 1
          reservations[2], // spoke 2
          reservations[3], // spoke 3
          reservations[0], // center (placed last, removed first)
        ],
        anchor: Point<int>(cx, cy),
      );
      return placement;
    }
    return null;
  }
}
