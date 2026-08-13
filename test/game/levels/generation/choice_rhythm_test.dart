// P4 — choice rhythm: the shape of the player's choice over time, as opposed
// to the FSR aggregate which only reports how much of it there is.

import 'package:chain_pop/game/levels/generation/metrics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChoiceRhythm.fromTempoProfile', () {
    test('an empty profile is zero', () {
      expect(ChoiceRhythm.fromTempoProfile(const []), ChoiceRhythm.zero);
    });

    test('a fully forced corridor is one long run with no choice', () {
      final r = ChoiceRhythm.fromTempoProfile(const [1, 1, 1, 1, 1, 1]);
      expect(r.longestForcedRun, 6);
      expect(r.multiChoiceFraction, 0.0);
      expect(r.directionChanges, 0);
    });

    test('a fully open board is all choice and no forced run', () {
      final r = ChoiceRhythm.fromTempoProfile(const [5, 5, 5, 5]);
      expect(r.longestForcedRun, 0);
      expect(r.multiChoiceFraction, 1.0);
      expect(r.directionChanges, 0);
    });

    test('counts only genuine reversals, ignoring flat steps', () {
      // up, flat, up, down, down, up  → two reversals.
      final r = ChoiceRhythm.fromTempoProfile(const [1, 3, 3, 5, 4, 2, 6]);
      expect(r.directionChanges, 2);
    });

    test('longest forced run is the longest, not the last', () {
      final r = ChoiceRhythm.fromTempoProfile(const [1, 1, 1, 4, 1, 1]);
      expect(r.longestForcedRun, 3);
      expect(r.multiChoiceFraction, closeTo(1 / 6, 1e-9));
    });

    test('a zero-choice step counts as forced (dead end, not a decision)', () {
      final r = ChoiceRhythm.fromTempoProfile(const [2, 0, 0, 2]);
      expect(r.longestForcedRun, 2);
      expect(r.multiChoiceFraction, 0.5);
    });

    test('separates two boards with identical FSR but different shape', () {
      // Same length, same mean, same count of forced steps — but one front-loads
      // all the constraint into a single corridor and the other alternates.
      const corridor = [1, 1, 1, 1, 5, 5, 5, 5];
      const alternating = [1, 5, 1, 5, 1, 5, 1, 5];

      final a = ChoiceRhythm.fromTempoProfile(corridor);
      final b = ChoiceRhythm.fromTempoProfile(alternating);

      expect(a.multiChoiceFraction, b.multiChoiceFraction);
      expect(a.longestForcedRun, 4);
      expect(b.longestForcedRun, 1);
      expect(b.directionChanges, greaterThan(a.directionChanges));
      // The alternating board is the better-rhythm candidate.
      expect(b.rankingScore, greaterThan(a.rankingScore));
    });

    test('ranking prefers more choice at equal run length', () {
      final open = ChoiceRhythm.fromTempoProfile(const [1, 4, 4, 4]);
      final tight = ChoiceRhythm.fromTempoProfile(const [1, 4, 1, 4]);
      expect(open.rankingScore, greaterThan(tight.rankingScore));
    });
  });
}
