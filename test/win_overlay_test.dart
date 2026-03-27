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
}

void _noop() {}
