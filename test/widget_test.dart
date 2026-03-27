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
}
