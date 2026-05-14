import 'package:chain_pop/services/ads/hint_ad_policy.dart';
import 'package:chain_pop/services/ads/undo_ad_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HintAdPolicy', () {
    test('free budget then cooldown gating', () async {
      final p = HintAdPolicy(
        freeBudget: 2,
        coolDown: const Duration(milliseconds: 80),
      );
      expect(p.hasFreeHint, isTrue);
      expect(p.needsRewardedForNextHint(), isFalse);
      expect(p.remainingCooldownIfBlocked(), isNull);

      p.recordFreeHint();
      expect(p.hasFreeHint, isTrue);
      p.recordFreeHint();
      expect(p.hasFreeHint, isFalse);
      expect(p.needsRewardedForNextHint(), isTrue);

      p.recordRewardedHint();
      final remaining1 = p.remainingCooldownIfBlocked();
      expect(remaining1, isNotNull);
      expect(remaining1!.inMilliseconds, greaterThan(0));

      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(p.remainingCooldownIfBlocked(), isNull);
    });

    test('resetForNewAttempt restores free hints', () {
      final p = HintAdPolicy(freeBudget: 1);
      p.recordFreeHint();
      expect(p.hasFreeHint, isFalse);
      p.resetForNewAttempt();
      expect(p.hasFreeHint, isTrue);
    });
  });

  group('UndoAdPolicy', () {
    test('free budget then cooldown gating', () async {
      final p = UndoAdPolicy(
        freeBudget: 2,
        coolDown: const Duration(milliseconds: 80),
      );
      expect(p.hasFreeUndo, isTrue);
      expect(p.needsRewardedForNextUndo(), isFalse);

      p.recordFreeUndo();
      p.recordFreeUndo();
      expect(p.hasFreeUndo, isFalse);
      p.recordRewardedUndo();
      expect(p.remainingCooldownIfBlocked(), isNotNull);

      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(p.remainingCooldownIfBlocked(), isNull);
    });

    test('resetForNewAttempt restores free undos', () {
      final p = UndoAdPolicy(freeBudget: 1);
      p.recordFreeUndo();
      expect(p.hasFreeUndo, isFalse);
      p.resetForNewAttempt();
      expect(p.hasFreeUndo, isTrue);
    });
  });
}
