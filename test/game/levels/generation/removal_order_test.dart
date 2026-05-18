import 'dart:math';
import 'dart:ui';

import 'package:chain_pop/game/levels/generation/removal_order.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('single cell always has an order', () {
    final r = Random(1);
    final o = tryGreedyEliminationOrder(
      [const Point(3, 3)],
      8,
      8,
      r,
    );
    expect(o, isNotNull);
    expect(o!.length, 1);
  });

  test('full 4x4 grid often finds an order', () {
    final pos = <Point<int>>[];
    for (var y = 0; y < 4; y++) {
      for (var x = 0; x < 4; x++) {
        pos.add(Point(x, y));
      }
    }
    var found = 0;
    for (var seed = 0; seed < 30; seed++) {
      final o = tryGreedyEliminationOrder(
        pos,
        4,
        4,
        Random(seed),
        maxAttempts: 120,
      );
      if (o != null && o.length == 16) found++;
    }
    expect(found, greaterThan(20),
        reason: 'greedy should almost always succeed on a small full grid');
  });
}
