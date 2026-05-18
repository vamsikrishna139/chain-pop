import 'dart:math';

import 'package:chain_pop/game/levels/generation/diversity_ledger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recentStrictMarginCount covering window matches legacy novelty', () {
    const window = 12;
    final legacy =
        DiversityLedger(windowSize: window, hammingThreshold: 5, sameVisualFamilyHammingMargin: 3);
    final wideStrict = DiversityLedger(
      windowSize: window,
      hammingThreshold: 5,
      sameVisualFamilyHammingMargin: 3,
      recentStrictMarginCount: window + 48,
    );
    expect(wideStrict.recentStrictMarginCount,
        greaterThanOrEqualTo(window));

    final rng = Random(31415);
    for (var step = 0; step < 400; step++) {
      final bits = rng.nextInt(1 << 24);
      final fp = LevelFingerprint(bits);
      expect(
        legacy.isNovel(fp),
        equals(wideStrict.isNovel(fp)),
        reason: 'step $step disagreement on bits=0x${bits.toRadixString(16)}',
      );
      legacy.record(fp);
      wideStrict.record(fp);
    }
  });
}
