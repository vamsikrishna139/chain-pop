import 'dart:io';

import 'package:chain_pop/game/levels/tutorial_levels.dart';
import 'package:chain_pop/models/game_settings.dart';
import 'package:chain_pop/screens/game_screen.dart';
import 'package:chain_pop/screens/main_menu_screen.dart';
import 'package:chain_pop/services/storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('chain_pop_menu_test_');
    Hive.init(tempDir.path);
    await StorageService.init();
  });

  setUp(() async {
    await StorageService.clearProgress();
    await StorageService.saveGameSettings(
      const GameSettings(soundEnabled: false, hapticsEnabled: false),
    );
  });

  /// Hive I/O must not run on the widget test's fake-async clock; see
  /// [WidgetTester.runAsync].
  Future<void> storageForWidgetTest(
    WidgetTester tester,
    Future<void> Function() work,
  ) =>
      tester.runAsync(work);

  Future<void> pumpMenu(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: MainMenuScreen()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  group('MainMenuScreen tutorial entry', () {
    testWidgets('shows Tutorial when onboarding is not completed', (tester) async {
      expect(StorageService.tutorialCompleted, isFalse);
      await pumpMenu(tester);

      expect(find.text('Tutorial'), findsOneWidget);
      expect(find.text('Replay tutorial'), findsNothing);

      expect(
        find.descendant(
          of: find.byType(FilledButton),
          matching: find.text('Tutorial'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('shows Replay tutorial when onboarding is completed', (tester) async {
      await storageForWidgetTest(tester, () async {
        await StorageService.setTutorialCompleted(true);
      });
      expect(StorageService.tutorialCompleted, isTrue);

      await pumpMenu(tester);

      expect(find.text('Replay tutorial'), findsOneWidget);
      expect(find.text('Tutorial'), findsNothing);

      expect(
        find.descendant(
          of: find.byType(OutlinedButton),
          matching: find.text('Replay tutorial'),
        ),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Replay tutorial'), findsOneWidget);
    });

    testWidgets('Tutorial tap opens GameScreen in tutorial mode', (tester) async {
      await pumpMenu(tester);

      await tester.tap(find.text('Tutorial'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final screen = tester.widget<GameScreen>(find.byType(GameScreen));
      expect(screen.isTutorial, isTrue);
      expect(screen.tutorialIndex, 0);
      expect(screen.fixedLevel, tutorialLevels.first);
      expect(screen.level, 1);
    });

    testWidgets('Replay tutorial tap opens same GameScreen tutorial mode', (tester) async {
      await storageForWidgetTest(tester, () async {
        await StorageService.setTutorialCompleted(true);
      });

      await pumpMenu(tester);

      await tester.tap(find.text('Replay tutorial'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final screen = tester.widget<GameScreen>(find.byType(GameScreen));
      expect(screen.isTutorial, isTrue);
      expect(screen.tutorialIndex, 0);
      expect(screen.fixedLevel, tutorialLevels.first);
    });
  });
}
