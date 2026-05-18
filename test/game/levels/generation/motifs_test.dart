import 'dart:math';

import 'package:chain_pop/game/levels/generation/motifs.dart';
import 'package:chain_pop/game/levels/generation/sightline_table.dart';
import 'package:chain_pop/game/levels/grid_cell_key.dart';
import 'package:chain_pop/game/levels/level.dart';
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

void main() {
  group('motifCatalogue', () {
    test('exposes the four Phase-4 motifs', () {
      final ids = motifCatalogue().map((m) => m.id).toList();
      expect(
        ids,
        containsAll(<MotifId>[
          MotifId.escapeChord,
          MotifId.diamondIntersection,
          MotifId.clusterKey,
          MotifId.staircase,
        ]),
      );
    });

    test('every motif places successfully on a 10x10 rectangle', () {
      final sightlines = SightlineTable.forGrid(10, 10);
      final silhouette = _fullRect(10, 10);
      for (final motif in motifCatalogue()) {
        var placedAtLeastOnce = false;
        for (var seed = 0; seed < 32; seed++) {
          final p = motif.place(
            gridWidth: 10,
            gridHeight: 10,
            silhouette: silhouette,
            sightlines: sightlines,
            random: Random(seed),
          );
          if (p != null) {
            placedAtLeastOnce = true;
            // All reservations must live inside the silhouette and be unique.
            expect(p.reservations.length, greaterThanOrEqualTo(3));
            final keys =
                p.reservations.map((r) => r.cellKey).toSet();
            expect(keys.length, p.reservations.length,
                reason: '${motif.id} produced duplicate cells');
            for (final r in p.reservations) {
              expect(silhouette.contains(r.cellKey), isTrue);
              expect(r.position.x, inInclusiveRange(0, 9));
              expect(r.position.y, inInclusiveRange(0, 9));
            }
          }
        }
        expect(placedAtLeastOnce, isTrue,
            reason: '${motif.id} failed to place in 32 attempts on a 10x10');
      }
    });

    test('placements fail gracefully when silhouette is tiny', () {
      // 3x3 grid → most motifs cannot fit at all.
      final sightlines = SightlineTable.forGrid(3, 3);
      final silhouette = _fullRect(3, 3);
      for (final motif in motifCatalogue()) {
        final p = motif.place(
          gridWidth: 3,
          gridHeight: 3,
          silhouette: silhouette,
          sightlines: sightlines,
          random: Random(7),
          maxAttempts: 4,
        );
        // Either fits in a 3x3 (very rare) or returns null. Both fine.
        if (p != null) {
          for (final r in p.reservations) {
            expect(silhouette.contains(r.cellKey), isTrue);
          }
        }
      }
    });
  });

  group('MotifReservation', () {
    test('cellKey matches grid_cell_key.dart helper', () {
      const r =
          MotifReservation(position: Point<int>(3, 4), direction: Direction.up);
      expect(r.cellKey, gridCellKey(3, 4));
    });
  });

  group('sampleMotif', () {
    test('only returns motifs from the catalogue', () {
      final catalogueIds =
          motifCatalogue().map((m) => m.id).toSet();
      for (var seed = 0; seed < 50; seed++) {
        final motif = sampleMotif(Random(seed));
        expect(catalogueIds.contains(motif.id), isTrue);
      }
    });
  });
}
