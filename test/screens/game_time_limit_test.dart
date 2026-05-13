import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/screens/game/game_time_limit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('computeTutorialCountdownSec', () {
    test('first four steps get 60s, final step 45s', () {
      expect(computeTutorialCountdownSec(0), 60);
      expect(computeTutorialCountdownSec(3), 60);
      expect(computeTutorialCountdownSec(4), 45);
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
}
