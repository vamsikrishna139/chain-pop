import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/screens/win_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('win overlay can be disposed before star timers fire',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: WinOverlay(
            levelId: 1,
            difficulty: DifficultyMode.easy,
            stars: 3,
            jamCount: 0,
            timeTaken: Duration(seconds: 12),
            onMainMenu: _noop,
            onRetry: _noop,
            onNextLevel: _noop,
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
  });

  testWidgets('win overlay can be disposed between staggered star timers',
      (tester) async {
    // Timer 1 fires at 200 ms, timer 2 at 340 ms, timer 3 at 480 ms.
    // Dispose at 350 ms: timers 1 & 2 have already fired; timer 3 has not.
    // The dispose() call cancels timer 3 before it can call .forward() on an
    // already-disposed AnimationController.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: WinOverlay(
            levelId: 5,
            difficulty: DifficultyMode.easy,
            stars: 2,
            jamCount: 3,
            timeTaken: Duration(seconds: 45),
            onMainMenu: _noop,
            onRetry: _noop,
            onNextLevel: _noop,
          ),
        ),
      ),
    );

    // Let timers 1 and 2 fire.
    await tester.pump(const Duration(milliseconds: 350));

    // Dispose the overlay.
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));

    // Advance past where timer 3 would have fired — must not throw.
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
  });
}

void _noop() {}
