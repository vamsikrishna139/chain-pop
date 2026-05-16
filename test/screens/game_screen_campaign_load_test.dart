import 'dart:io';

import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/level.dart';
import 'package:chain_pop/game/levels/tutorial_levels.dart';
import 'package:chain_pop/screens/game_screen.dart';
import 'package:chain_pop/services/ads/no_op_ad_service.dart';
import 'package:chain_pop/services/game_audio.dart';
import 'package:chain_pop/services/storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final tempDir =
        await Directory.systemTemp.createTemp('chain_pop_campaign_load_');
    Hive.init(tempDir.path);
    await StorageService.init();
  });

  setUp(() async {
    await StorageService.clearProgress();
  });

  LevelData tinySolvableLevel(int level, DifficultyMode mode) => LevelData(
        levelId: level,
        gridWidth: 3,
        gridHeight: 3,
        nodes: [
          NodeData(id: 0, x: 0, y: 0, dir: Direction.up),
        ],
      );

  testWidgets(
    'deferred campaign load shows gate then resolved level from builder',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(
            level: 3,
            difficulty: DifficultyMode.medium,
            adService: NoOpAdService(),
            audioHandleFactory: SilentGameAudioHandle.new,
            campaignLevelBuilder: tinySolvableLevel,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Building level…'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w.runtimeType.toString().startsWith('GameWidget'),
        ),
        findsNothing,
      );

      await tester.idle();
      await tester.pump();

      expect(find.text('Building level…'), findsNothing);
      expect(
        find.byWidgetPredicate(
          (w) => w.runtimeType.toString().startsWith('GameWidget'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'campaignLevelBuilder error falls back to emergency layout',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(
            level: 7,
            difficulty: DifficultyMode.hard,
            adService: NoOpAdService(),
            audioHandleFactory: SilentGameAudioHandle.new,
            campaignLevelBuilder: (_, __) => throw StateError('test throw'),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Building level…'), findsOneWidget);

      await tester.idle();
      await tester.pump();

      expect(find.text('Building level…'), findsNothing);
      expect(
        find.byWidgetPredicate(
          (w) => w.runtimeType.toString().startsWith('GameWidget'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('tutorial fixedLevel skips async loading gate', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(
          level: 1,
          difficulty: DifficultyMode.easy,
          fixedLevel: tutorialLevels[0],
          isTutorial: true,
          tutorialIndex: 0,
          adService: NoOpAdService(),
          audioHandleFactory: SilentGameAudioHandle.new,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Building level…'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (w) => w.runtimeType.toString().startsWith('GameWidget'),
      ),
      findsOneWidget,
    );
  });
}
