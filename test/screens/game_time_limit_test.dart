import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/screens/game/game_time_limit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('computeTutorialCountdownSec', () {
    test('movement steps get 60s, recap 45s, mechanic intros 60s', () {
      expect(computeTutorialCountdownSec(0), 60);
      expect(computeTutorialCountdownSec(3), 60);
      expect(computeTutorialCountdownSec(4), 45);
      expect(computeTutorialCountdownSec(5), 60);
      expect(computeTutorialCountdownSec(7), 60);
      expect(computeTutorialCountdownSec(8), 60);
    });

    test('graduation board (index 9) gets 90s for all five arrow types', () {
      expect(computeTutorialCountdownSec(9), 90);
    });
  });

  group('computeGameTimeLimit — easy', () {
    test('returns generous countdown that grows with node count', () {
      final a = computeGameTimeLimit(DifficultyMode.easy, 3, 1)!;
      final b = computeGameTimeLimit(DifficultyMode.easy, 10, 1)!;
      expect(b, greaterThan(a));
      expect(a, greaterThanOrEqualTo(120));
    });

    test('never exceeds four minutes', () {
      expect(
        computeGameTimeLimit(DifficultyMode.easy, 999, 1),
        lessThanOrEqualTo(240),
      );
    });

    test('slightly tighter on high level ids but still bounded', () {
      final low = computeGameTimeLimit(DifficultyMode.easy, 8, 5)!;
      final high = computeGameTimeLimit(DifficultyMode.easy, 8, 120)!;
      expect(high, lessThanOrEqualTo(low));
      expect(high, greaterThanOrEqualTo(120));
    });
  });

  group('computeGameTimeLimit — hard', () {
    test('returns countdown scaled by node count and level', () {
      final small = computeGameTimeLimit(DifficultyMode.hard, 20, 30)!;
      final large = computeGameTimeLimit(DifficultyMode.hard, 45, 30)!;
      expect(small, greaterThanOrEqualTo(25));
      expect(small, lessThanOrEqualTo(150));
      expect(large, greaterThan(small));
    });

    test('higher level ids get slightly less time', () {
      final early = computeGameTimeLimit(DifficultyMode.hard, 30, 10)!;
      final late = computeGameTimeLimit(DifficultyMode.hard, 30, 200)!;
      expect(late, lessThanOrEqualTo(early));
    });
  });
}
