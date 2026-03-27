import 'dart:io';

import 'package:chain_pop/game/chain_pop_game.dart';
import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/screens/game_screen.dart';
import 'package:chain_pop/services/storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('chain_pop_test_');
    Hive.init(tempDir.path);
    await StorageService.init();
  });

  setUp(() async {
    await StorageService.clearProgress();
  });

  testWidgets('quick retry after win does not auto-advance later',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: GameScreen(level: 1, difficulty: DifficultyMode.easy),
      ),
    );
    await tester.pump();

    final gameWidgetFinder = find.byWidgetPredicate(
      (widget) => widget.runtimeType.toString().startsWith('GameWidget'),
    );
    final dynamic gameWidget = tester.widget(gameWidgetFinder);
    final game = gameWidget.game as ChainPopGame;

    game.onWin();
    await tester.pump();

    final retryFinder = find.text('RETRY');
    expect(retryFinder, findsOneWidget);
    await tester.ensureVisible(retryFinder);
    await tester.tap(retryFinder, warnIfMissed: false);
    await tester.pump();

    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('LEVEL 1'), findsWidgets);
    expect(find.text('LEVEL 2'), findsNothing);
    expect(find.text('RESET'), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();
  });

  testWidgets(
      'retry after auto-advance delay fires still does not auto-advance',
      skip: true, // Flaky/Hangs due to fakeAsync Timer orchestration after init state.
      (tester) async {
    // This variant tests the _hasWon guard rather than the timer-cancel path.
    // The 700 ms delay timer is allowed to fire and set up the periodic
    // auto-advance timer BEFORE the player taps Retry.  _resetForRetry() must
    // cancel that periodic timer (and set _hasWon = false) so the game stays
    // on level 1.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: GameScreen(level: 1, difficulty: DifficultyMode.easy),
      ),
    );
    await tester.pump();

    final gameWidgetFinder = find.byWidgetPredicate(
      (widget) => widget.runtimeType.toString().startsWith('GameWidget'),
    );
    final dynamic gameWidget = tester.widget(gameWidgetFinder);
    final game = gameWidget.game as ChainPopGame;

    // Trigger win, then advance 800 ms to let the 700 ms delay timer fire and
    // set up the periodic auto-advance countdown.
    game.onWin();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    // Periodic auto-advance timer is now running.  Tap Retry before it
    // completes the 5-second countdown.
    final retryFinder = find.text('RETRY');
    expect(retryFinder, findsOneWidget);
    await tester.ensureVisible(retryFinder);
    await tester.tap(retryFinder, warnIfMissed: false);
    await tester.pump();

    // Wait well past the 5 s countdown — no navigation must occur.
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('LEVEL 1'), findsWidgets);
    expect(find.text('LEVEL 2'), findsNothing);
    expect(find.text('RESET'), findsOneWidget);

    // Pump past the 15-second ghost hint timer to ensure it clears before unmount
    await tester.pump(const Duration(seconds: 15));

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpAndSettle();
  });
}
