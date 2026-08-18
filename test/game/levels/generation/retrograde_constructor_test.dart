import 'dart:math';

import 'package:chain_pop/game/levels/generation/candidate_scorer.dart';
import 'package:chain_pop/game/levels/generation/metrics.dart';
import 'package:chain_pop/game/levels/generation/motifs.dart';
import 'package:chain_pop/game/levels/generation/retrograde_constructor.dart';
import 'package:chain_pop/game/levels/generation/sightline_table.dart';
import 'package:chain_pop/game/levels/grid_cell_key.dart';
import 'package:chain_pop/game/levels/level.dart';
import 'package:chain_pop/game/levels/level_solver.dart';
import 'package:flutter_test/flutter_test.dart';

Set<int> _fullRect(int w, int h) {
  final out = <int>{};
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      out.add(gridCellKey(x, y));
    }
  }
  return out;
}

LevelData _levelFromPlacements(
  int w,
  int h,
  List<RetrogradePlacement> placements,
) {
  final nodes = <NodeData>[
    for (var i = 0; i < placements.length; i++)
      NodeData(
        id: i,
        x: placements[i].position.x,
        y: placements[i].position.y,
        dir: placements[i].direction,
      ),
  ];
  return LevelData(
    levelId: 0,
    gridWidth: w,
    gridHeight: h,
    nodes: nodes,
  );
}

bool _validatesByIdOrder(LevelData level) {
  final remaining = level.nodes.map((n) => n.clone()).toList();
  final sorted = List<NodeData>.from(level.nodes)
    ..sort((a, b) => a.id.compareTo(b.id));
  for (final n in sorted) {
    if (!LevelSolver.canRemove(n, remaining, level)) return false;
    remaining.removeWhere((r) => r.id == n.id);
  }
  return remaining.isEmpty;
}

/// First node id hit along [nodeId]'s assigned direction, or null if ray exits.
int? _firstRayTarget(LevelData level, int nodeId) {
  final node = level.nodes.firstWhere((n) => n.id == nodeId);
  var x = node.x;
  var y = node.y;
  while (true) {
    switch (node.dir) {
      case Direction.up:
        y--;
        break;
      case Direction.down:
        y++;
        break;
      case Direction.left:
        x--;
        break;
      case Direction.right:
        x++;
        break;
    }
    if (x < 0 || x >= level.gridWidth || y < 0 || y >= level.gridHeight) {
      return null;
    }
    for (final other in level.nodes) {
      if (other.id == nodeId) continue;
      if (other.x == x && other.y == y) return other.id;
    }
  }
}

void main() {
  group('RetrogradeConstructor', () {
    test('zero target returns an empty placement list', () {
      final ctor = RetrogradeConstructor(
        gridWidth: 4,
        gridHeight: 4,
        silhouette: _fullRect(4, 4),
        targetNodeCount: 0,
        scorer: CandidateScorer(),
        sightlines: SightlineTable.forGrid(4, 4),
        random: Random(0),
      );
      final result = ctor.construct();
      expect(result, isNotNull);
      expect(result!.isEmpty, isTrue);
    });

    test('target larger than silhouette returns null', () {
      final ctor = RetrogradeConstructor(
        gridWidth: 3,
        gridHeight: 3,
        silhouette: _fullRect(3, 3),
        targetNodeCount: 10,
        scorer: CandidateScorer(),
        sightlines: SightlineTable.forGrid(3, 3),
        random: Random(0),
      );
      expect(ctor.construct(), isNull);
    });

    test('5x5 with 12 nodes is solvable by removing in returned order', () {
      final ctor = RetrogradeConstructor(
        gridWidth: 5,
        gridHeight: 5,
        silhouette: _fullRect(5, 5),
        targetNodeCount: 12,
        scorer: CandidateScorer(),
        sightlines: SightlineTable.forGrid(5, 5),
        random: Random(123),
      );
      final placements = ctor.construct();
      expect(placements, isNotNull);
      expect(placements!.length, equals(12));
      final level = _levelFromPlacements(5, 5, placements);
      expect(_validatesByIdOrder(level), isTrue);
      // Removal-wave count is at least 1 (solver verifies a full clear).
      expect(LevelSolver.countRemovalWaves(level), greaterThan(0));
    });

    test('produces deterministic output for the same seed', () {
      List<RetrogradePlacement> run(int seed) {
        final ctor = RetrogradeConstructor(
          gridWidth: 6,
          gridHeight: 6,
          silhouette: _fullRect(6, 6),
          targetNodeCount: 18,
          scorer: CandidateScorer(),
          sightlines: SightlineTable.forGrid(6, 6),
          random: Random(seed),
        );
        final result = ctor.construct();
        expect(result, isNotNull);
        return result!;
      }

      final a = run(99);
      final b = run(99);
      expect(a.length, equals(b.length));
      for (var i = 0; i < a.length; i++) {
        expect(a[i].position, equals(b[i].position));
        expect(a[i].direction, equals(b[i].direction));
      }
    });

    test('different seeds usually produce different placements', () {
      List<RetrogradePlacement> run(int seed) {
        final ctor = RetrogradeConstructor(
          gridWidth: 6,
          gridHeight: 6,
          silhouette: _fullRect(6, 6),
          targetNodeCount: 18,
          scorer: CandidateScorer(),
          sightlines: SightlineTable.forGrid(6, 6),
          random: Random(seed),
        );
        return ctor.construct()!;
      }

      var diffs = 0;
      for (var s = 1; s < 20; s++) {
        final a = run(s);
        final b = run(s + 1000);
        // Strict equality across all positions is unlikely for distinct seeds.
        var same = a.length == b.length;
        if (same) {
          for (var i = 0; i < a.length; i++) {
            if (a[i].position != b[i].position ||
                a[i].direction != b[i].direction) {
              same = false;
              break;
            }
          }
        }
        if (!same) diffs++;
      }
      expect(diffs, greaterThan(15),
          reason: 'softmax should produce variety across seeds');
    });

    test('dense 4x4 (14 nodes) — every returned level is solvable', () {
      // Dense fills exercise the rollback path. We don't require guaranteed
      // success on every seed (the legacy path is the safety net for that
      // until Phase 3), only that whatever the constructor returns is valid.
      var solved = 0;
      for (var s = 0; s < 12; s++) {
        final ctor = RetrogradeConstructor(
          gridWidth: 4,
          gridHeight: 4,
          silhouette: _fullRect(4, 4),
          targetNodeCount: 14,
          scorer: CandidateScorer(),
          sightlines: SightlineTable.forGrid(4, 4),
          random: Random(s),
        );
        final placements = ctor.construct();
        if (placements == null) continue;
        expect(placements.length, equals(14));
        final level = _levelFromPlacements(4, 4, placements);
        expect(_validatesByIdOrder(level), isTrue,
            reason: 'every returned level must be solvable in ID order');
        solved++;
      }
      expect(solved, greaterThan(6),
          reason: 'retrograde should clear most semi-dense 4x4 boards');
    });

    // ── Phase 4 — Motif Transaction Block reservations
    test(
        'honours motif reservations and places them at the start of removal '
        'order (deferred motif-only board)', () {
      // Zero bulk slots before motifs — exercises motif phase alone. Removal
      // order lists deferred motifs first (last steps of forward construction).
      final reservations = <MotifReservation>[
        const MotifReservation(
            position: Point<int>(0, 0), direction: Direction.left),
        const MotifReservation(
            position: Point<int>(3, 0), direction: Direction.right),
        const MotifReservation(
            position: Point<int>(0, 3), direction: Direction.left),
        const MotifReservation(
            position: Point<int>(3, 3), direction: Direction.right),
      ];
      final ctor = RetrogradeConstructor(
        gridWidth: 4,
        gridHeight: 4,
        silhouette: _fullRect(4, 4),
        targetNodeCount: 4,
        scorer: CandidateScorer(),
        sightlines: SightlineTable.forGrid(4, 4),
        random: Random(7),
        reservations: reservations,
      );
      final placements = ctor.construct();
      expect(placements, isNotNull);
      expect(placements!.length, equals(4));
      final level = _levelFromPlacements(4, 4, placements);
      expect(_validatesByIdOrder(level), isTrue,
          reason: 'motif-bearing level must still be solvable');

      final reservedCells = {
        for (final r in reservations) gridCellKey(r.position.x, r.position.y),
      };
      final head = placements.sublist(0, 4);
      final headKeys =
          head.map((p) => gridCellKey(p.position.x, p.position.y)).toSet();
      expect(headKeys, equals(reservedCells));
      for (final p in head) {
        final match = reservations.firstWhere((r) => r.position == p.position);
        expect(p.direction, equals(match.direction));
      }
    });

    test(
        'motif sub-phase deadlock degrades motifs but still fills '
        'targetNodeCount on a full rectangle', () {
      // Interior ring blocks rays into a 2×2 centre — motifs almost always
      // fail here, triggering degrade; bulk should still reach the count.
      const cx = 3;
      const cy = 3;
      final reservations = <MotifReservation>[
        const MotifReservation(
            position: Point<int>(cx, cy - 1), direction: Direction.up),
        const MotifReservation(
            position: Point<int>(cx, cy + 1), direction: Direction.down),
        const MotifReservation(
            position: Point<int>(cx - 1, cy), direction: Direction.left),
        const MotifReservation(
            position: Point<int>(cx + 1, cy),
            direction: Direction.right),
      ];
      final ctor = RetrogradeConstructor(
        gridWidth: 6,
        gridHeight: 6,
        silhouette: _fullRect(6, 6),
        targetNodeCount: 16,
        scorer: CandidateScorer(),
        sightlines: SightlineTable.forGrid(6, 6),
        random: Random(12345),
        reservations: reservations,
      );
      final placements = ctor.construct();
      expect(placements, isNotNull);
      expect(placements!.length, equals(16));
      final keys = placements
          .map((p) => gridCellKey(p.position.x, p.position.y))
          .toSet();
      expect(keys.length, equals(16));
    });

    test('returns null when reservation lives outside the silhouette', () {
      // (10, 10) is well off a 4x4 grid; the motif placement must abort.
      final reservations = <MotifReservation>[
        const MotifReservation(
            position: Point<int>(10, 10), direction: Direction.up),
      ];
      final ctor = RetrogradeConstructor(
        gridWidth: 4,
        gridHeight: 4,
        silhouette: _fullRect(4, 4),
        targetNodeCount: 8,
        scorer: CandidateScorer(),
        sightlines: SightlineTable.forGrid(4, 4),
        random: Random(0),
        reservations: reservations,
      );
      expect(ctor.construct(), isNull);
    });

    test('returns null when reservations exceed the target node count', () {
      final reservations = <MotifReservation>[
        for (var i = 0; i < 5; i++)
          MotifReservation(
              position: Point<int>(i, 0), direction: Direction.up),
      ];
      final ctor = RetrogradeConstructor(
        gridWidth: 5,
        gridHeight: 5,
        silhouette: _fullRect(5, 5),
        targetNodeCount: 3, // less than reservations.length
        scorer: CandidateScorer(),
        sightlines: SightlineTable.forGrid(5, 5),
        random: Random(0),
        reservations: reservations,
      );
      expect(ctor.construct(), isNull);
    });

    test('post-placement reassignment applies crunch blocking toward lower IDs',
        () {
      var crunchFlips = 0;
      var solvable = 0;
      for (var s = 0; s < 32; s++) {
        final ctor = RetrogradeConstructor(
          gridWidth: 7,
          gridHeight: 7,
          silhouette: _fullRect(7, 7),
          targetNodeCount: 28,
          scorer: CandidateScorer(
            crunchBlockingProbability: 0.72,
            weights: const ScorerWeights(temperature: 0.01),
          ),
          sightlines: SightlineTable.forGrid(7, 7),
          random: Random(s + 900),
        );
        final placements = ctor.construct();
        if (placements == null) continue;
        solvable++;
        crunchFlips += ctor.reassignmentCrunchFlips;
        final level = _levelFromPlacements(7, 7, placements);
        expect(_validatesByIdOrder(level), isTrue);
      }
      expect(solvable, greaterThan(10));
      expect(crunchFlips, greaterThan(0),
          reason: 'reassignment should flip crunch-window directions');
    });

    test('reassignment only points at lower-ID nodes on the ray', () {
      for (var s = 0; s < 16; s++) {
        final ctor = RetrogradeConstructor(
          gridWidth: 6,
          gridHeight: 6,
          silhouette: _fullRect(6, 6),
          targetNodeCount: 24,
          scorer: CandidateScorer(crunchBlockingProbability: 1.0),
          sightlines: SightlineTable.forGrid(6, 6),
          random: Random(s + 1500),
        );
        final placements = ctor.construct();
        if (placements == null) continue;
        final level = _levelFromPlacements(6, 6, placements);
        expect(_validatesByIdOrder(level), isTrue);

        final n = placements.length;
        final crunchStart = (n * 0.35).floor().clamp(1, n - 1);
        final crunchEnd = (n * 0.65).ceil().clamp(crunchStart, n - 1);
        for (var i = crunchStart; i <= crunchEnd; i++) {
          final target = _firstRayTarget(level, i);
          if (target != null) {
            expect(
              target,
              lessThan(i),
              reason: 'node $i must not point at higher-ID node $target',
            );
          }
        }
      }
    });

    test('solvability retry preserves ID-order extraction', () {
      var solvable = 0;
      for (var s = 0; s < 20; s++) {
        final scorer = CandidateScorer(
          crunchBlockingProbability: 0.72,
        );
        final ctor = RetrogradeConstructor(
          gridWidth: 7,
          gridHeight: 7,
          silhouette: _fullRect(7, 7),
          targetNodeCount: 28,
          scorer: scorer,
          sightlines: SightlineTable.forGrid(7, 7),
          random: Random(s + 1200),
        );
        final placements = ctor.construct();
        if (placements == null) continue;
        solvable++;
        final level = _levelFromPlacements(7, 7, placements);
        expect(_validatesByIdOrder(level), isTrue);
      }
      expect(solvable, greaterThan(8));
    });

    test('canonical removal order preserves ID-order solvability', () {
      var solvable = 0;
      for (var s = 0; s < 24; s++) {
        final ctor = RetrogradeConstructor(
          gridWidth: 6,
          gridHeight: 6,
          silhouette: _fullRect(6, 6),
          targetNodeCount: 22,
          scorer: CandidateScorer(),
          sightlines: SightlineTable.forGrid(6, 6),
          random: Random(s + 500),
        );
        final placements = ctor.construct();
        if (placements == null) continue;
        expect(placements.length, equals(22));
        final level = _levelFromPlacements(6, 6, placements);
        expect(_validatesByIdOrder(level), isTrue);
        solvable++;
      }
      expect(solvable, greaterThan(12));
    });

    test('scored reassignment prefers blocked targets when available', () {
      var blockedTargetCount = 0;
      var blockingFlipCount = 0;
      for (var s = 0; s < 32; s++) {
        final ctor = RetrogradeConstructor(
          gridWidth: 7,
          gridHeight: 7,
          silhouette: _fullRect(7, 7),
          targetNodeCount: 28,
          scorer: CandidateScorer(crunchBlockingProbability: 1.0),
          sightlines: SightlineTable.forGrid(7, 7),
          random: Random(s + 4100),
        );
        final placements = ctor.construct();
        if (placements == null) continue;
        final level = _levelFromPlacements(7, 7, placements);
        expect(_validatesByIdOrder(level), isTrue);

        final n = placements.length;
        final crunchStart = (n * 0.35).floor().clamp(1, n - 1);
        final crunchEnd = (n * 0.65).ceil().clamp(crunchStart, n - 1);
        for (var i = crunchStart; i <= crunchEnd; i++) {
          final target = _firstRayTarget(level, i);
          if (target == null) continue;
          blockingFlipCount++;
          if (_firstRayTarget(level, target) != null) blockedTargetCount++;
        }
      }
      expect(blockingFlipCount, greaterThan(0));
      expect(
        blockedTargetCount / blockingFlipCount,
        greaterThan(0.35),
        reason: 'scored picks should favor already-blocked chain nodes',
      );
    });

    test('seeded dense configs produce chainDepthMax >= 2 where possible', () {
      var maxDepth = 0;
      var deepLevels = 0;
      var solvable = 0;
      for (var s = 0; s < 48; s++) {
        final ctor = RetrogradeConstructor(
          gridWidth: 7,
          gridHeight: 7,
          silhouette: _fullRect(7, 7),
          targetNodeCount: 28,
          scorer: CandidateScorer(crunchBlockingProbability: 0.85),
          sightlines: SightlineTable.forGrid(7, 7),
          random: Random(s + 3000),
        );
        final placements = ctor.construct();
        if (placements == null) continue;
        solvable++;
        final level = _levelFromPlacements(7, 7, placements);
        expect(_validatesByIdOrder(level), isTrue);
        final depth = level.nodes.isEmpty
            ? 0
            : LevelTopologyMetrics.compute(level).chainDepthMax;
        if (depth > maxDepth) maxDepth = depth;
        if (depth >= 2) deepLevels++;
      }
      expect(solvable, greaterThan(10));
      expect(maxDepth, greaterThanOrEqualTo(2));
      expect(deepLevels, greaterThan(0));
    });
  });
}
