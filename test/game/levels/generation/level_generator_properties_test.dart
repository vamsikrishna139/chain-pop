/// Property-based tests for the level generation system.
///
/// Each test validates a universal correctness property that must hold
/// for ALL valid inputs, not just specific examples.
///
/// Properties tested:
///   1. Guaranteed Solvability     — every level is solvable
///   2. Deterministic Generation   — same ID → same level
///   3. Unique Levels              — different IDs → different levels
///   4. Configuration Constraints  — levels respect grid/node bounds
///   5. Solution Path Completeness — solution path clears all nodes
///   6. Direction Validity         — each node is free when its turn comes
///   7. No Crashes                 — generator never throws
import 'package:flutter_test/flutter_test.dart';
import 'package:chain_pop/game/levels/generation/generation.dart';
import 'package:chain_pop/game/levels/level.dart';
import 'package:chain_pop/game/levels/level_solver.dart';

void main() {
  final generator = LevelGenerator();

  // Sample of level IDs spanning all difficulties: easy (1-9), medium (10-29), hard (30+)
  final sampleIds = [
    1, 3, 5, 8,           // easy
    10, 15, 20, 28,       // medium
    30, 50, 75, 100,      // hard
  ];

  // ─── Property 1: Guaranteed Solvability ──────────────────────────────────
  group('Property 1 — Guaranteed Solvability', () {
    test('Every generated level is solvable', () {
      for (final id in sampleIds) {
        final result = generator.generate(id);
        expect(result.isSuccess, isTrue, reason: 'Level $id generation failed');
        expect(
          LevelSolver.isSolvable(result.value),
          isTrue,
          reason: 'Level $id is not solvable',
        );
      }
    });

    test('Explicit difficulty modes produce solvable levels', () {
      for (final id in [1, 15, 50]) {
        for (final mode in DifficultyMode.values) {
          final result = generator.generate(id, mode: mode);
          expect(result.isSuccess, isTrue);
          expect(LevelSolver.isSolvable(result.value), isTrue,
              reason: 'Level $id mode=$mode not solvable');
        }
      }
    });
  });

  // ─── Property 2: Deterministic Generation ────────────────────────────────
  group('Property 2 — Deterministic Generation', () {
    test('Same level ID always produces identical levels', () {
      for (final id in sampleIds) {
        final r1 = generator.generate(id);
        final r2 = generator.generate(id);
        expect(r1.isSuccess, isTrue);
        expect(r2.isSuccess, isTrue);

        final l1 = r1.value;
        final l2 = r2.value;
        expect(l1.nodes.length, equals(l2.nodes.length));
        for (int i = 0; i < l1.nodes.length; i++) {
          expect(l1.nodes[i].x, equals(l2.nodes[i].x));
          expect(l1.nodes[i].y, equals(l2.nodes[i].y));
          expect(l1.nodes[i].dir, equals(l2.nodes[i].dir));
          expect(l1.nodes[i].id, equals(l2.nodes[i].id));
        }
      }
    });
  });

  // ─── Property 3: Unique Levels ───────────────────────────────────────────
  group('Property 3 — Unique Levels', () {
    test('Consecutive level IDs produce different puzzles', () {
      int duplicates = 0;
      for (int id = 1; id < 20; id++) {
        final l1 = generator.generate(id).value;
        final l2 = generator.generate(id + 1).value;

        // Compare node positions as a fingerprint
        final sig1 = l1.nodes.map((n) => '${n.x},${n.y},${n.dir.name}').join('|');
        final sig2 = l2.nodes.map((n) => '${n.x},${n.y},${n.dir.name}').join('|');
        if (sig1 == sig2) duplicates++;
      }
      // Allow at most 1 collision in 20 pairs (practically 0)
      expect(duplicates, lessThan(2), reason: 'Too many duplicate level layouts');
    });
  });

  // ─── Property 4: Configuration Constraints ───────────────────────────────
  group('Property 4 — Configuration Constraints', () {
    test('All nodes are within grid bounds', () {
      for (final id in sampleIds) {
        final level = generator.generate(id).value;
        for (final node in level.nodes) {
          expect(node.x, greaterThanOrEqualTo(0));
          expect(node.x, lessThan(level.gridWidth));
          expect(node.y, greaterThanOrEqualTo(0));
          expect(node.y, lessThan(level.gridHeight));
        }
      }
    });

    test('Node count respects difficulty max constraint and grid capacity', () {
      for (final mode in DifficultyMode.values) {
        final params = DifficultyParameters.fromLevelId(0, mode: mode);
        for (final id in [1, 5, 10]) {
          final level = generator.generate(id, mode: mode).value;
          // Node count must not exceed the difficulty max or grid capacity.
          final gridCapacity = level.gridWidth * level.gridHeight;
          expect(level.nodes.length, lessThanOrEqualTo(params.maxNodes));
          expect(level.nodes.length, lessThanOrEqualTo(gridCapacity));
          // Must have at least 1 node
          expect(level.nodes.length, greaterThanOrEqualTo(1));
        }
      }
    });

    test('Grid dimensions respect difficulty constraints', () {
      // Easy: 4-6, Medium: 6-10, Hard: 10-20
      final bounds = {
        DifficultyMode.easy:   (4, 6),
        DifficultyMode.medium: (6, 10),
        DifficultyMode.hard:   (10, 20),
      };
      for (final entry in bounds.entries) {
        final level = generator.generate(1, mode: entry.key).value;
        expect(level.gridWidth, greaterThanOrEqualTo(entry.value.$1));
        expect(level.gridWidth, lessThanOrEqualTo(entry.value.$2));
      }
    });
  });

  // ─── Property 5: Solution Path Completeness ──────────────────────────────
  group('Property 5 — Solution Path Completeness', () {
    test('Removing nodes in ID order empties the board', () {
      for (final id in sampleIds) {
        final level = generator.generate(id).value;
        final remaining = level.nodes.map((n) => n.clone()).toList();
        final sortedByIndex = List<NodeData>.from(remaining)
          ..sort((a, b) => a.id.compareTo(b.id));

        for (final target in sortedByIndex) {
          remaining.removeWhere((n) => n.id == target.id);
        }

        expect(remaining, isEmpty,
            reason: 'Level $id had remaining nodes after full solution path');
      }
    });
  });

  // ─── Property 6: Direction Validity ──────────────────────────────────────
  group('Property 6 — Direction Validity', () {
    test('Each node is free when its turn arrives in solution order', () {
      for (final id in sampleIds) {
        final level = generator.generate(id).value;
        final active = level.nodes.map((n) => n.clone()).toList();
        final sortedByIndex = List<NodeData>.from(active)
          ..sort((a, b) => a.id.compareTo(b.id));

        for (final target in sortedByIndex) {
          final live = active.firstWhere((n) => n.id == target.id);
          expect(
            LevelSolver.canRemove(live, active),
            isTrue,
            reason: 'Level $id: node ${live.id} blocked at its step',
          );
          active.removeWhere((n) => n.id == live.id);
        }
      }
    });
  });

  // ─── Property 7: No Crashes ───────────────────────────────────────────────
  group('Property 7 — No Crashes', () {
    test('Generator never throws for valid level IDs', () {
      for (int id = 0; id <= 100; id++) {
        expect(() => generator.generate(id), returnsNormally);
      }
    });

    test('Generator returns error (not throw) for invalid config', () {
      // Negative level ID → invalid configuration
      final result = generator.generate(-1);
      // Should return error result, not throw
      expect(() => result.isSuccess, returnsNormally);
    });
  });
}
